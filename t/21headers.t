use strict;
use Test::More tests => 3;
use LWP::UserAgent;
use HTTP::Proxy;
use t::Utils;    # some helper functions for the server

my $test = Test::Builder->new;
my @pids;

# this is to work around tests in forked processes
$test->use_numbers(0);
$test->no_ending(1);

# create a HTTP::Daemon (on an available port)
my $server = server_start();

# create and fork the proxy
my $proxy = HTTP::Proxy->new( port => 0, maxconn => 1 );
$proxy->init;    # required to access the url later
$proxy->agent->no_proxy( URI->new( $server->url )->host );
push @pids, fork_proxy($proxy);

# fork the HTTP server
my $pid = fork;
die "Unable to fork web server" if not defined $pid;

if ( $pid == 0 ) {

    # the answer method
    my $answer = sub {
        my $req  = shift;
        my $data = shift;
        ok(
            !$req->headers->header('Proxy-Connection'),
            "Proxy-Connection: header filtered"
        );
        ok( $req->headers->header('Via'), "Server says Via: header added" );
        return HTTP::Response->new(
            200, 'OK',
            HTTP::Headers->new( 'Content-Type' => 'text/plain' ),
            "Headers checked."
        );
    };

    # let's return some files when asked for them
    server_next( $server, $answer );

    exit 0;
}

push @pids, $pid;

# run a client
my $ua = LWP::UserAgent->new;
$ua->proxy( http => $proxy->url );

# send a Proxy-Connection header
my $req = HTTP::Request->new( GET => $server->url . "proxy-connection" );
$req->headers->header( Proxy_Connection => 'Keep-Alive' );
my $rep = $ua->simple_request($req);
ok( $rep->headers->header('Via'), "Client says Via: header added" );

# make sure both kids are dead
wait for @pids;
