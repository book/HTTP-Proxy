use Test::More;
use strict;
use t::Utils; use HTTP::Proxy;
use LWP::UserAgent;
use IO::Socket::INET;

plan skip_all => "This test fails on MSWin32. HTTP::Proxy is usable on Win32 with maxchild => 0"
  if $^O eq 'MSWin32';

# test CONNECT
my $test = Test::Builder->new;

# this is to work around tests in forked processes
$test->use_numbers(0);
$test->no_ending(1);

# fork a local server that'll print a banner on connection
my $host;
my $banner = "President_of_Earth Barbarella Professor_Ping Stomoxys Dildano\n";
{

    my $server = IO::Socket::INET->new( Listen => 1 );
    plan 'skip_all', "Couldn't create local server" if !defined $server;

    $host = 'localhost:' . $server->sockport;
    my $pid = fork;
    plan 'skip_all', "Couldn't fork" if !defined $pid;
    if ( !$pid ) {
        my $sock = $server->accept;
        $sock->print($banner);
        $sock->close;
        exit;
    }

}

plan tests => 4;

{
    my $proxy = HTTP::Proxy->new( port => 0, max_connections => 1 );
    $proxy->init;    # required to access the url later

    # fork a HTTP proxy
    my $pid = fork_proxy(
        $proxy,
        sub {
            ok( $proxy->conn == 1, "Served the correct number of requests" );
        }
    );

    # wait for the server and proxy to be ready
    sleep 1;

    # run a client
    my $ua = LWP::UserAgent->new;
    $ua->proxy( https => $proxy->url );

    my $req = HTTP::Request->new( CONNECT => "https://$host/" );
    my $res = $ua->request($req);
    my $sock = $res->{client_socket};


    my $read;
    is( $res->code, 200, "The proxy accepts CONNECT requests" );
    ok( $sock->sysread( $read, 100 ), "Read some data from the socket" );
    is( $read, $banner, "CONNECTed to the TCP server and got the banner" );
    close $sock;

    # make sure the kids are dead
    wait for 1 .. 2;
}
