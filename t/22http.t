use strict;
use vars qw( @requests );

# here are all the requests the client will try
BEGIN {
@requests = (
  [ 'http://www.perdu.com/', 200 ],
  [ 'http://httpd.apache.org/docs', 301 ],
  [ 'http://www.perl.com/testing/', 404 ],
  [ 'http://www.error.zzz/', 500 ],
);
}

use Test::More tests => @requests + 1;
use HTTP::Daemon;
use LWP::UserAgent;
use HTTP::Proxy;

# shall we skip tests if the network is not available?

my $test = Test::Builder->new;

# this is to work around tests in forked processes
$test->use_numbers(0);
$test->no_ending(1);

my $proxy = HTTP::Proxy->new( port => 0, maxconn => scalar @requests );
$proxy->init;    # required to access the url later

# fork a HTTP proxy
my @pids;
my $pid = fork;
die "Unable to fork proxy" if not defined $pid;

if ( $pid == 0 ) {

    # this is the http proxy
    $proxy->start;
    ok( $proxy->conn == @requests, "Served the correct number of requests" );
    exit 0;
}

# back in the parent
push @pids, $pid;    # remember the kid

# run a client
my $ua = LWP::UserAgent->new;
$ua->proxy( http => $proxy->url );

for (@requests) {
    my $req = HTTP::Request->new( GET => $_->[0] );
    my $rep = $ua->simple_request($req);
    is( $rep->code, $_->[1], "Got an answer (@{[$rep->code]})" );
}

# make sure both kids are dead
wait for @pids;
