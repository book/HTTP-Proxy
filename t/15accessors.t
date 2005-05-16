use Test::More;
use HTTP::Proxy qw( :log );

my $proxy;

$proxy = HTTP::Proxy->new;

#
# default values
#

my %meth = (
    agent           => undef,
    chunk           => 4096,
    daemon          => undef,
    host            => 'localhost',
    logfh           => *main::STDERR,
    #maxchild        => 10,
    #maxconn         => 0,
    max_connections => 0,
    #maxserve        => 10,
    max_keep_alive_requests => 10,
    port            => 8080,
    request         => undef,
    response        => undef,
    hop_headers     => undef,
    logmask         => 0,
    x_forwarded_for => 1,
    conn            => 0,
    client_socket   => undef,
    # loop is not used/internal for now
);

plan tests => 11 + keys %meth;

for my $key ( sort keys %meth ) {
    no strict 'refs';
    is( $proxy->$key(), $meth{$key}, "$key has the correct default" );
}

like( $proxy->via(), qr!\(HTTP::Proxy/$HTTP::Proxy::VERSION\)$!,
      "via has the correct default");

# test deprecated accessors
$proxy = HTTP::Proxy->new( maxserve => 127,  maxconn => 255 );
is( $proxy->max_keep_alive_requests, 127, "deprecated maxserve");
is( $proxy->max_connections, 255, "deprecated maxconn");

#
# test generated accessors (they're all the same)
#

is( $proxy->port(8888), $meth{port}, "Set return the previous value" );
is( $proxy->port, 8888, "Set works" );

#
# other accessors
#

$proxy->max_clients( 666 );
is( $proxy->engine->max_clients, 666, "max_clients correctly delegated" );

# check the url() method
$proxy->port(0);

# this spits a (normal) warning, but we clean it away
{
    local *OLDERR;

    # swap errputs
    open OLDERR, ">&STDERR" or die "Could not duplicate STDERR: $!";
    close STDERR;

    # the actual test
    is( $proxy->url, undef, "We do not have a url yet" );

    # put things back to normal
    close STDERR;
    open STDERR, ">&OLDERR" or die "Could not duplicate OLDERR: $!";
    close OLDERR;
}

$proxy->_init_daemon;
ok( $proxy->url =~ '^$http://' . $proxy->host . ':\d+/$', "url looks good" );

# check the timeout
$proxy->_init_agent;
is( $proxy->agent->timeout, 60, "Default agent timeout of 60 secs" );
is( $proxy->timeout(120), 60, "timeout() returns the old value" );
is( $proxy->agent->timeout, 120, "New agent timeout value of 120 secs" );
