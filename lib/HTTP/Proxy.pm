package HTTP::Proxy;

use HTTP::Daemon;
use LWP::UserAgent;
use LWP::ConnCache;
use Carp;

use strict;
use vars qw( $VERSION $AUTOLOAD );

$VERSION = 0.01;

=pod

=head1 NAME

HTTP::Proxy - A pure Perl HTTP proxy

=head1 SYNOPSIS

    use HTTP::Proxy;

    # initialisation
    my $proxy = HTTP::Proxy->new( port =>

    # alternate initialisation
    my $proxy = HTTP::Proxy->new;
    $proxy->port( 8080 ); # the classical accessors are here!
    
    # this is a MainLoop-like method
    $proxy->start;

=head1 DESCRIPTION


=head1 METHODS

=head2 Constructor

=cut

sub new {
    my $class = shift;

    # some defaults
    my $self = {
        agent   => undef,
        daemon  => undef,
        host    => 'localhost',
        maxconn => 0,
        port    => 8080,
        verbose => 0,
        @_,
    };

    # non modifiable defaults
    %$self = ( %$self, conn => 0, logfh => *STDERR );
    return bless $self, $class;
}

=head2 Accessors

The HTTP::Proxy has several accessors. They are all AUTOLOADed,
and read-write. Called with arguments, the accessor returns the
current value. Called with a single argument, it set the current
value and returns the previous one, in case you want to keep it.

The defined accessors are (in alphabetical order):

=over 4

=item agent

The LWP::UserAgent object used internally to connect to remote sites.

=item daemon

The HTTP::Daemon object used to accept incoming connections.
(You usually never need this.)

=item host

The proxy HTTP::Daemon host (default: 'localhost').

=item maxconn

The maximum number of connections the proxy will accept before returning
from start(). 0 (the default) means never stop accepting connections.

=item port

The proxy HTTP::Daemon port (default: 8080).

=item conn (read-only)

The number of connections processed by this HTTP::Proxy instance.

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
    if ( $attr =~ /^(?:agent|daemon|host|maxconn
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

This method works like a Tk MainLoop: you hand over control to the
HTTP::Proxy object you created and configured.

If C<maxconn> is not zero, start() will return after processing
at most that many connections.

=cut

sub start {
    my $self = shift;

    $self->init if ( !defined $self->daemon or !defined $self->agent );

    my $daemon = $self->daemon;
    while ( my $conn = $daemon->accept ) {
        $self->process($conn);
        $conn->close;
        undef $conn;
        $self->conn( $self->conn + 1 );
        last if $self->maxconn && $self->conn >= $self->maxconn;
    }
    return 1;
}

#
# init methods
#

sub init {
    my $self = shift;

    $self->init_daemon if ( !defined $self->daemon );
    $self->init_agent  if ( !defined $self->agent );
}

sub init_daemon {
    my $self = shift;
    my $daemon = HTTP::Daemon->new(
        LocalHost => $self->host,
        LocalPort => $self->port,
        ReuseAddr => 1,
      )
      or die "Cannot initialize proxy daemon: $!";
    $self->daemon($daemon);
    return $daemon;
}

sub init_agent {
    my $self = shift;
    my $cache = LWP::ConnCache->new;
    my $agent = LWP::UserAgent->new(
        conn_cache            => $cache,
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
            $self->log( "Getting request failed:", $conn->reason );
            return;
        }
        $self->log( "Request:\n" . $req->as_string );
        my $res = $self->agent->send_request($req);
        $conn->print( $res->as_string );
        $self->log( "Response:\n" . $res->headers->as_string );
    }
}

sub log {
    my $self = shift;
    print { $self->logfh } "[" . localtime() . "] @_\n";
}

=head2 Callbacks

=cut

1;
