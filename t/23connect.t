use Test::More;
use strict;
use lib 't/lib';
use ProxyUtils;
use HTTP::Proxy;
use LWP::UserAgent;
use IO::Socket::INET;

plan skip_all => "This test fails on MSWin32. HTTP::Proxy is usable on Win32 with maxchild => 0"
  if $^O eq 'MSWin32';

# make sure we inherit no upstream proxy
delete $ENV{$_} for qw( http_proxy HTTP_PROXY https_proxy HTTPS_PROXY );

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

    # run a client
    my $ua = LWP::UserAgent->new;
    $ua->proxy( http => $proxy->url );

    my $req = HTTP::Request->new( CONNECT => "http://$host/" );
    my $res = $ua->request($req);
    my $sock = $res->{client_socket};
    if ( !$sock->blocking ) {
        diag("socket is non blocking, switching to blocking mode");
        $sock->blocking(1);
    }

    # what does the proxy say?
    is( $res->code, 200, "The proxy accepts CONNECT requests" );

    # read a line
    my $read;
    eval {
        local $SIG{ALRM} = sub { die 'timeout' };
        alarm 30;
        $read = <$sock>;
    };

    ok( $read, "Read some data from the socket" );
    is( $read, $banner, "CONNECTed to the TCP server and got the banner" );
    close $sock;

    # make sure the kids are dead
    wait for 1 .. 2;
}
