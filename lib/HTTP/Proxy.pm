package HTTP::Proxy;

use HTTP::Daemon;
use LWP::UserAgent;
use LWP::ConnCache;
use CGI;
use Fcntl ':flock';    # import LOCK_* constants
use POSIX;
use Carp;

use strict;
use vars qw( $VERSION $AUTOLOAD );

$VERSION = 0.03;

=pod

=head1 NAME

HTTP::Proxy - A pure Perl HTTP proxy

=head1 SYNOPSIS

    use HTTP::Proxy;

    # initialisation
    my $proxy = HTTP::Proxy->new( port => 3128 );

    # alternate initialisation
    my $proxy = HTTP::Proxy->new;
    $proxy->port( 3128 ); # the classical accessors are here!

    # you can also use your own UserAgent
    my $agent = LWP::RobotUA->new;
    $proxy->agent( $agent );

    # this is a MainLoop-like method
    $proxy->start;

=head1 DESCRIPTION

This module implements a HTTP Proxy, using a HTTP::Daemon to accept
client connections, and a LWP::UserAgent to ask for the requested pages.

=head1 METHODS

=head2 Constructor

=cut

sub new {
    my $class = shift;

    # some defaults
    my $self = {
        agent    => undef,
        control  => 'proxy',
        daemon   => undef,
        host     => 'localhost',
        maxchild => 10,
        maxconn  => 0,
        logfh    => *STDERR,
        port     => 8080,
        verbose  => 0,
        @_,
    };

    # non modifiable defaults
    %$self = ( %$self, conn => 0, loop => 1 );
    bless $self, $class;

    # ugly way to set control_regex
    $self->control( $self->control );

    return $self;
}

# AUTOLOADed attributes
my $all_attr = qr/^(?:agent|conn|control_regex|daemon|host|logfh|loop|
                      maxchild|maxconn|port|verbose)$/x;

# read-only attributes
my $ro_attr = qr/^(?:conn|control_regex|loop)$/;

=head2 Accessors

The HTTP::Proxy has several accessors. They are all AUTOLOADed.

Called with arguments, the accessor returns the current value.
Called with a single argument, it set the current value and
returns the previous one, in case you want to keep it.

If you call a read-only accessor with a parameter, this parameter
will be ignored.

The defined accessors are (in alphabetical order):

=over 4

=item agent

The LWP::UserAgent object used internally to connect to remote sites.

=item conn (read-only)

The number of connections processed by this HTTP::Proxy instance.

=item control

The default hostname for controlling the proxy (see L<CONTROL>).
The default is "C<proxy>", which corresponds to the URL
http://proxy/, where port is the listening port of the proxy).

=cut

sub control {
    my $self = shift;
    my $old  = $self->{control};
    if (@_) {
        my $control = shift;
        $self->{control}       = $control;
        $self->{control_regex} = qr!^http://$control(?:/(\w+))?!;
    }
    return $old;
}

# control_regex is private

=item daemon

The HTTP::Daemon object used to accept incoming connections.
(You usually never need this.)

=item host

The proxy HTTP::Daemon host (default: 'localhost').

=item logfh

A filehandle to a logfile (default: *STDERR).

=item maxchild

The maximum number of child process the HTTP::Proxy object will spawn
to handle client requests (default: 16).

=item maxconn

The maximum number of connections the proxy will accept before returning
from start(). 0 (the default) means never stop accepting connections.

=item port

The proxy HTTP::Daemon port (default: 8080).

=item url (read-only)

The url where the proxy can be reached.

=cut

sub url {
    my $self = shift;
    if ( not defined $self->daemon ) {
        carp "HTTP daemon not started yet";
        return undef;
    }
    return $self->daemon->url;
}

=item verbose

Be verbose in the logs (default: 0).

Here are the various log levels:
 0 - All errors
 1 - Requested URL, reponse status and total number of connections processed
 2 -
 3 - Subprocesses information (fork, wait, etc.)
 4 -
 5 - Full request and response headers are sent along

=back

=cut

sub AUTOLOAD {

    # we don't DESTROY
    return if $AUTOLOAD =~ /::DESTROY/;

    # fetch the attribute name
    $AUTOLOAD =~ /.*::(\w+)/;
    my $attr = $1;

    # must be one of the registered subs
    if ( $attr =~ $all_attr ) {
        no strict 'refs';
        my $rw = 1;
        $rw = 0 if $attr =~ $ro_attr;

        # create and register the method
        *{$AUTOLOAD} = sub {
            my $self = shift;
            my $old  = $self->{$attr};
            $self->{$attr} = shift if @_ && $rw;
            return $old;
        };

        # now do it
        goto &{$AUTOLOAD};
    }
    croak "Undefined method $AUTOLOAD";
}

=head2 The start() method

This method works like Tk's C<MainLoop>: you hand over control to the
HTTP::Proxy object you created and configured.

If C<maxconn> is not zero, start() will return after accepting
at most that many connections.

=cut

sub start {
    my $self = shift;
    $self->init;

    my @kids;
    my $reap;
    my $hupped;

    # zombies reaper
    my $reaper;
    $reaper = sub {
        $reap++;
        $SIG{CHLD} = $reaper;    # for sysV systems
    };
    $SIG{CHLD} = $reaper;
    $SIG{HUP}  = sub { $hupped++ };

    # the main loop
    my $daemon = $self->daemon;
    while ( $self->loop ) {

        # prefork children process
        for ( 1 .. $self->maxchild - @kids ) {

            my $child = fork;
            if ( !defined $child ) {
                $self->log( 0, "Cannot fork" );
                $self->maxchild( $self->maxchild - 1 ) if $self->maxchild > 1;
                next;
            }

            # the parent process
            if ($child) {
                $self->log( 3, "Preforked child process $child" );
                push @kids, $child;
            }

            # the child process handles the whole connection
            else {
                my $conn = $daemon->accept;
                $SIG{INT} = 'IGNORE';
                $self->process($conn);
                exit;    # let's die!
            }
        }

        # wait for a signal
        POSIX::pause();

        # handle zombies
        while ($reap) {
            my $pid = wait;
            @kids = grep { $_ != $pid } @kids;
            $self->{conn}++;    # Cannot use the interface for RO attributes
            $self->log( 3, "Reaped child process $pid" );
            $reap--;
        }

        # did a child send us information?
        if ($hupped) {

            # TODO
        }

        # this was the last child we forked
        last if $self->maxconn && $self->conn >= $self->maxconn;
    }

    # wait for remaining children
    $self->log( 3, "Remaining kids: @kids" );
    kill INT => @kids;

    while (@kids) {
        my $pid = wait;
        @kids = grep { $_ != $pid } @kids;
        $self->log( 3, "Waited for child process $pid" );
    }

    $self->log( 1, "Processed " . $self->conn . " connection(s)" );
    return $self->conn;
}

# semi-private init method
sub init {
    my $self = shift;

    $self->_init_daemon if ( !defined $self->daemon );
    $self->_init_agent  if ( !defined $self->agent );

    # specific agent config
    $self->agent->requests_redirectable( [] );
    $self->agent->protocols_allowed(     [qw( http https ftp gopher )] );
    return;
}

#
# private init methods
#

sub _init_daemon {
    my $self = shift;
    my %args = (
        LocalHost => $self->host,
        LocalPort => $self->port,
        ReuseAddr => 1,
    );
    delete $args{LocalPort} unless $self->port;    # 0 means autoselect
    my $daemon = HTTP::Daemon->new(%args)
      or die "Cannot initialize proxy daemon: $!";
    $daemon->product_tokens("HTTP-Daemon/$VERSION");
    $self->daemon($daemon);
    return $daemon;
}

sub _init_agent {
    my $self  = shift;
    my $agent = LWP::UserAgent->new(
        env_proxy  => 1,
        keep_alive => 2,
      )
      or die "Cannot initialize proxy agent: $!";
    $self->agent($agent);
    return $agent;
}

=head2 Other methods

=over 4

=cut

sub process {
    my ( $self, $conn ) = @_;
    my $response;
    my $req = $conn->get_request();

    unless ( defined $req ) {
        $self->log( 0, "Getting request failed:", $conn->reason );
    }

    # can we serve this protocol?
    if ( !$self->agent->is_protocol_supported( my $s = $req->uri->scheme ) ) {
        $response = new HTTP::Response( 501, 'Not Implemented' );
        $response->content(
            "Scheme $s is not supported by the proxy's LWP::UserAgent");
        goto SEND;    # yuck :-)
    }

    # massage the request to pop a response
    $req->headers->remove_header('Proxy-Connection');    # broken header
    $self->log( 1, "($$) Request:", $req->uri );
    $self->log( 5, "($$) Request:", $req->headers->as_string );
    $response = $self->agent->simple_request($req);

  SEND:

    # remove Connection: headers from the response
    $response->headers->header( Connection => 'close' );

    # send the response
    if ( $req->uri->scheme =~ /^(?:ftp|gopher)$/ && $response->is_success ) {
        $conn->print( $response->content );
    }
    else {
        $conn->print( $response->as_string );
    }
    $self->log( 1, "($$) Response:", $response->status_line );
    $self->log( 5, "($$) Response:", $response->headers->as_string );
}

=item log( $level, $message )

Adds $message at the end of C<logfh>, if $level is greater than C<verbose>,
the log() method also prints a timestamp.

=cut

sub log {
    my $self  = shift;
    my $level = shift;
    my $fh    = $self->logfh;

    return if $self->verbose < $level;

    my ( $prefix, $msg ) = ( @_, '' );
    my @lines = split /\n/, $msg;
    @lines = ('') if not @lines;

    flock( $fh, LOCK_EX );
    print $fh "[" . localtime() . "] $prefix $_\n" for @lines;
    flock( $fh, LOCK_UN );
}

=back

=head2 Callbacks

You can alter the way the default HTTP::Proxy works by pluging callbacks
at different stages of the request/response handling.

(TO BE IMPLEMENTED)

=cut

=head1 BUGS

Some connections to the client are never closed.
(HTTP::Proxy should handle the client and the server connection separately.)

=head1 TODO

* Provide an interface for logging.

* Provide control over the proxy through special URLs

=head1 AUTHOR

Philippe "BooK" Bruhat, E<lt>book@cpan.orgE<gt>.

=head1 THANKS

Many people helped me during the development of this module, either on
mailing-lists, irc, or over a beer in a pub...

So, in no particular order, thanks to Michael Schwern (testing while forking),
Eric 'echo' Cholet (preforked processes).

=head1 COPYRIGHT

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

1;
