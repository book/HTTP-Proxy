use Test::More tests => 7;
use HTTP::Proxy;

my $proxy;

$proxy = HTTP::Proxy->new;

# check defaults
is( $proxy->verbose, 0,           "Default is no logging" );
is( $proxy->port,    8080,        "Default port 8080" );
is( $proxy->host,    'localhost', "Default host localhost" );
is( $proxy->logfh, *STDERR, "Default logging to STDERR" );

# set/get data
$proxy->port(8888);
is( $proxy->port, 8888, "Changed port" );

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

