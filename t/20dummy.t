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

use Test::More tests => 3 * @requests + 1;

use LWP::UserAgent;
use HTTP::Proxy;
use t::Utils;    # some helper functions for the server

my $test = Test::Builder->new;

# this is to work around tests in forked processes
$test->use_numbers(0);
$test->no_ending(1);

# create a HTTP::Daemon (on an available port)
my $server = server_start();

my $proxy = HTTP::Proxy->new( port => 0, maxconn => scalar @requests );
$proxy->init;    # required to access the url later

# fork the HTTP server
my @pids;
my $pid = fork;
die "Unable to fork web server" if not defined $pid;

if ( $pid == 0 ) {

    # the answer method
    my $answer = sub {
        my $req  = shift;
        my $data = shift;
        ok( $req->uri =~ quotemeta, "The daemon got what it expected" );
        return HTTP::Response->new(
            200, 'OK',
            HTTP::Headers->new( 'Content-Type' => 'text/plain' ),
            "Here is $data."
        );
    };

    # let's return some files when asked for them
    server_next( $server, $answer, $_ ) for @requests;

    exit 0;
}

# back in the parent
push @pids, $pid;    # remember the kid

# fork a HTTP proxy
fork_proxy(
    $proxy,
    sub {
        is( $proxy->conn, @requests,
            "The proxy served the correct number of requests" );
    }
);

# back in the parent
push @pids, $pid;    # remember the kid

# run a client
my $ua = LWP::UserAgent->new;
$ua->proxy( http => $proxy->url );

for (@requests) {
    my $req = HTTP::Request->new( GET => $server->url . $_ );
    my $rep = $ua->simple_request($req);
    ok( $rep->is_success, "Got an answer (@{[$rep->status_line]})" );
    ok( $rep->content =~ quotemeta, "The client got what it expected" );
}

# make sure both kids are dead
wait for @pids;
