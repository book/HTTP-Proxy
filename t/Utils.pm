package t::Utils;

use strict;
use Exporter ();
use vars qw( @ISA @EXPORT @EXPORT_OK );

@ISA       = qw( Exporter );
@EXPORT    = qw( &server_start &server_next &fork_proxy );
@EXPORT_OK = @EXPORT;

use HTTP::Daemon;

# start a simple server
sub server_start {

    # create a HTTP::Daemon (on an available port)
    my $daemon = HTTP::Daemon->new(
        LocalHost => 'localhost',
        ReuseAddr => 1,
      )
      or die "Unable to start web server";
    return $daemon;
}

# This must NOT be called in an OO fashion but this way:
# server_next( $server, $coderef, ... );
#
# The optional coderef takes a HTTP::Request as its first argument
# and returns a HTTP::Response. The rest of server_next() arguments
# are passed to &$anwser;

sub server_next {
    my $daemon = shift;
    my $answer = shift;

    # get connection data
    my $conn = $daemon->accept;
    my $req  = $conn->get_request;

    # compute some answer
    my $rep;
    if ( ref $answer eq 'CODE' ) {
        $rep = $answer->( $req, @_ );
    }
    else {
        $rep = HTTP::Response->new(
            200, 'OK',
            HTTP::Headers->new( 'Content-Type' => 'text/plain' ),
            sprintf( "You asked for <a href='%s'>%s</a>", ( $req->uri ) x 2 )
        );
    }

    $conn->send_response($rep);
    $conn->close;
}

# run a stand-alone proxy
# the proxy accepts an optional coderef to run after serving all requests
sub fork_proxy {
    my $proxy = shift;
    my $sub   = shift;

    my $pid = fork;
    die "Unable to fork proxy" if not defined $pid;

    if ( $pid == 0 ) {

        # this is the http proxy
        $proxy->start;
        $sub->() if ( defined $sub and ref $sub eq 'CODE' );
        exit 0;
    }

    # back to the parent
    return $pid;
}
