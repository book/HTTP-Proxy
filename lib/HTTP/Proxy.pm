package HTTP::Proxy;

use HTTP::Daemon;
use LWP::UserAgent;
use LWP::ConnCache;
use Fcntl ':flock';    # import LOCK_* constants
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
        daemon   => undef,
        host     => 'localhost',
        maxchild => 16,
        maxconn  => 0,
        logfh    => *STDERR,
        port     => 8080,
        verbose  => 0,
        @_,
    };

    # non modifiable defaults
    %$self = ( %$self, conn => 0 );
    return bless $self, $class;
}

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

=back

=cut

sub AUTOLOAD {

    # we don't DESTROY
    return if $AUTOLOAD =~ /::DESTROY/;

    # fetch the attribute name
    $AUTOLOAD =~ /.*::(\w+)/;
    my $attr = $1;

    # must be one of the registered subs
    if (
        $attr =~ /^(?:agent|daemon|host|maxconn|maxchild
                      |logfh|port|conn|verbose)$/x
      )
    {
        no strict 'refs';
        my $rw = 1;
        $rw = 0 if $attr =~ /^(?:conn)$/;

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
    $SIG{CHLD} = sub { $reap++ };
    my $daemon = $self->daemon;
    while ( my $conn = $daemon->accept ) {
        my $child = fork;
        if ( !defined $child ) {

            # This could use a Retry-After: header...
            $conn->send_error( 503, "Proxy cannot fork" );
            $self->log( 0,          "Cannot fork" );
            next;
        }
        if ($child) {    # the parent process
            $self->{conn}++;    # Cannot use the interface for RO attributes
            $self->log( 3, "Forked child process $child" );
            push @kids, $child;

            # wait if there are more than maxchild kids
            last if $self->maxconn && $self->conn >= $self->maxconn;
            while ($reap) {
                my $pid = wait;
                $self->log( 3, "Reaped child process $pid" );
                $reap--;
            }
        }
        else {

            # the child process handles the connection
            $self->process($conn);
            $conn->close;
            undef $conn;
            exit;    # let's die!
        }
    }
    $self->log( 1, "Done " . $self->conn . " connection(s)" );
    return $self->conn;
}

sub init {
    my $self = shift;

    $self->_init_daemon if ( !defined $self->daemon );
    $self->_init_agent  if ( !defined $self->agent );
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
        env_proxy             => 1,
        keep_alive            => 2,
        requests_redirectable => [],
      )
      or die "Cannot initialize proxy agent: $!";
    $self->agent($agent);
    return $agent;
}

=head2 Other methods

=cut

sub process {
    my ( $self, $conn ) = @_;
    while ( my $req = $conn->get_request() ) {
        unless ( defined $req ) {
            $self->log( 0, "Getting request failed:", $conn->reason );
            return;
        }
        $self->log( 1, "($$) Request: " . $req->uri );
        $self->log( 5, "($$) Request: " . $req->headers->as_string );

        # handle the Connection: header from the request
        my $res = $self->agent->simple_request($req);
        $conn->print( $res->as_string );
        $self->log( 1, "($$) Response: " . $res->status_line );
        $self->log( 5, "($$) Response: " . $res->headers->as_string );
    }
}

sub log {
    my $self  = shift;
    my $level = shift;
    my $fh    = $self->logfh;

    return if $self->verbose < $level;

    flock( $fh, LOCK_EX );
    print $fh "[" . localtime() . "] $_\n" for @_;
    flock( $fh, LOCK_UN );
}

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
 
* Remove forking, so that all data is in one place

* Provide control over the proxy through special URLs

=head1 AUTHOR

Philippe "BooK" Bruhat, E<lt>book@cpan.orgE<gt>.

=head1 COPYRIGHT

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

1;
