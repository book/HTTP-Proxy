use strict;
use vars qw( @requests );

# here are all the requests the client will try
BEGIN {
    @requests = qw(
      file1.txt
      directory/file2.txt
      ooh.cgi?q=query
    );
}

use Test::More tests => 3 * @requests + 4;
use HTTP::Daemon;
use LWP::UserAgent;
use HTTP::Proxy;

my $test = Test::Builder->new;

# this is to work around tests in forked processes
$test->use_numbers(0);
$test->no_ending(1);

# create a HTTP::Daemon (on an available port)
my $daemon = HTTP::Daemon->new(
    LocalHost => 'localhost',
    ReuseAddr => 1,
  )
  or die "Unable to start web server";

my $proxy = HTTP::Proxy->new( port => 0, maxconn => scalar @requests );
$proxy->init;    # required to access the url later

# fork the HTTP server
my @pids;
my $pid = fork;
die "Unable to fork web server" if not defined $pid;

if ( $pid == 0 ) {

    # the answer method
    my $answer = sub {
        my ( $conn, $data ) = @_;
        my $h = HTTP::Headers->new( 'Content-Type' => 'text/plain' );
        my $rep = HTTP::Response->new( 200, 'OK', $h, "Here is $data." );
        $conn->send_response($rep);
    };

    # this is the http daemon
    # let's return some files when asked for them
    for (@requests) {
        my $conn = $daemon->accept;
        my $req  = $conn->get_request;
        ok( $req->uri =~ quotemeta, "The daemon got what it expected" );
        $answer->( $conn, $_ );
    }

    # Test the headers
    my $conn = $daemon->accept;
    my $req  = $conn->get_request;
    ok(
        !$req->headers->header('Proxy-Connection'),
        "Proxy-Connection: header filtered"
    );
    ok( $req->headers->header('Via'), "Server says Via: header added" );
    $answer->( $conn, 'Proxy-connection removed' );
    exit 0;
}

# back in the parent
push @pids, $pid;    # remember the kid

# fork a HTTP proxy
$pid = fork;
die "Unable to fork proxy" if not defined $pid;

if ( $pid == 0 ) {

    # this is the http proxy
    $proxy->start;
    ok( $proxy->conn == @requests,
        "The proxy served the correct number of requests" );
    exit 0;
}

# back in the parent
push @pids, $pid;    # remember the kid

# run a client
my $ua = LWP::UserAgent->new;
$ua->proxy( http => $proxy->url );

for (@requests) {
    my $req = HTTP::Request->new( GET => $daemon->url . $_ );
    my $rep = $ua->simple_request($req);
    ok( $rep->is_success, "Got an answer (@{[$rep->status_line]})" );
    ok( $rep->content =~ quotemeta, "The client got what it expected" );
}

# send a Proxy-Connection header
my $req = HTTP::Request->new( GET => $daemon->url . "proxy-connection" );
$req->headers->header( Proxy_Connection => 'Keep-Alive' );
my $rep = $ua->simple_request($req);
ok( $rep->headers->header('Via'), "Client says Via: header added" );

# make sure both kids are dead
wait for @pids;
