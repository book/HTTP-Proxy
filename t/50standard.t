use strict;
use Test::More tests => 5;
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
my $proxy = HTTP::Proxy->new( port => 0, maxconn => 2 );
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
    server_next($server);

    exit 0;
}

push @pids, $pid;

# run a client
my ( $req, $res );
my $ua = LWP::UserAgent->new;
$ua->proxy( http => $proxy->url );

# send a Proxy-Connection header
$req = HTTP::Request->new( GET => $server->url . "proxy-connection" );
$req->headers->header( Proxy_Connection => 'Keep-Alive' );
$res = $ua->simple_request($req);
ok( $res->headers->header('Via'), "Client says Via: header added" );

# check that we have single Date and Server headers
$req = HTTP::Request->new( GET => $server->url . "headers" );
$res = $ua->simple_request($req);
my @date = $res->headers->header('Date');
is( scalar @date, 1, "A single Date: header" );
my @server = $res->headers->header('Server');
is( scalar @server, 1, "A single Server: header" );

# we cannot check that the LWP Client-* headers are removed
# since we're using a LWP::UA to talk to the proxy

# make sure both kids are dead
wait for @pids;
