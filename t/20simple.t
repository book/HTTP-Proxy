#!/usr/bin/perl
use strict;
use Test::More tests => 10;
use HTTP::Daemon;
use LWP::UserAgent;
use HTTP::Proxy;
use Config;

my $test = Test::Builder->new;

# this is to work around tests in forked processes
$test->use_numbers(0);
$test->no_ending(1);

my $sig_kill;
{    # compute the KILL signal number
    my $i = 0;
    for ( split ' ', $Config{sig_name} ) {
        $sig_kill = $i, last if $_ eq 'KILL';
        $i++;
    }
}

# here are all the requests the client will try
my @requests = qw(
  file1.txt
  directory/file2.txt
  ooh.cgi?q=query
);

# reap the children
$SIG{CHLD} = sub { wait };

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

    # this is the http daemon
    # let's return some files when asked for them
    for (@requests) {
        my $conn = $daemon->accept;
        my $req  = $conn->get_request;
        ok( $req->uri =~ quotemeta, "The proxy requests what we expect" );
        my $h = HTTP::Headers->new( 'Content-Type' => 'text/plain' );
        my $rep = HTTP::Response->new( 200, 'OK', $h, "Here is $_." );
        $conn->send_response($rep);

        #$conn->close;
    }
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
    ok( $proxy->conn == @requests, "Served the correct number of requests" );
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
    ok( $rep->is_success, "Got an answer (@{[$rep->code]})" );
    ok( $rep->content =~ quotemeta, "Got what we wanted" );
}

# make sure the kids are dead
#sleep 5;
#for (@pids) { kill $sig_kill, $_ if kill 0, $_ }
