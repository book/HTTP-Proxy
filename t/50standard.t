use strict;
use Test::More tests => 8;
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
my $proxy = HTTP::Proxy->new( port => 0, maxconn => 4 );
$proxy->init;    # required to access the url later
$proxy->agent->no_proxy( URI->new( $server->url )->host );
push @pids, fork_proxy($proxy);

# fork the HTTP server
my $pid = fork;
die "Unable to fork web server" if not defined $pid;

if ( $pid == 0 ) {

    # let's return some files when asked for them
    server_next($server) for 1 .. 3;
    exit 0;
}

push @pids, $pid;

# run a client
my ( $req, $res );
my $ua = LWP::UserAgent->new;
$ua->proxy( http => $proxy->url );

#
# check that we have single Date and Server headers
#

# for GET requests
$req = HTTP::Request->new( GET => $server->url . "headers" );
$res = $ua->simple_request($req);
my @date = $res->headers->header('Date');
is( scalar @date, 1, "A single Date: header for GET request" );
my @server = $res->headers->header('Server');
is( scalar @server, 1, "A single Server: header for GET request" );

# for HEAD requests
$req = HTTP::Request->new( HEAD => $server->url . "headers-head" );
$res = $ua->simple_request($req);
my @date = $res->headers->header('Date');
is( scalar @date, 1, "A single Date: header for HEAD request" );
my @server = $res->headers->header('Server');
is( scalar @server, 1, "A single Server: header for HEAD request" );

# for direct proxy responses
$ua->proxy( file => $proxy->url );
$req = HTTP::Request->new( GET => "file:///etc/passwd" );
$res = $ua->simple_request($req);
my @date = $res->headers->header('Date');
is( scalar @date, 1, "A single Date: header for direct proxy response" );
my @server = $res->headers->header('Server');
is( scalar @server, 1, "A single Server: header for direct proxy response" );
# check the Server: header
like( $server[0], qr!HTTP::Proxy/\d+\.\d+!, "Correct server name for direct proxy response" );

# we cannot use a LWP user-agent to check
# that the LWP Client-* headers are removed
use IO::Socket::INET;

# connect directly to the proxy
$proxy->url() =~ /:(\d+)/;
my $sock = IO::Socket::INET->new(
    PeerAddr => 'localhost',
    PeerPort => $1,
    Proto    => 'tcp'
  ) or diag "Can't connect to the proxy";

# send the request
my $url = $server->url;
$url =~ m!http://([^:]*)!;
print $sock "GET $url HTTP/1.0\015\012Host: $1\015\012\015\012";  

# fetch and count the Client-* response headers
my @client = grep { /^Client-/ } <$sock>;
is( scalar @client, 0, "No Client-* headers sent by the proxy" );

# close the connection to the proxy
close $sock or diag "close: $!";

# make sure both kids are dead
wait for @pids;

