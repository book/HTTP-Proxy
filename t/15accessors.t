use Test::More tests => 13;
use HTTP::Proxy qw( :log );

my $proxy;

$proxy = HTTP::Proxy->new;

# check defaults
is( $proxy->logmask, NONE, "Default is no logging" );
is( $proxy->port, 8080,        "Default port 8080" );
is( $proxy->host, 'localhost', "Default host localhost" );
is( $proxy->logfh, *STDERR, "Default logging to STDERR" );
is( $proxy->timeout, 60, "Default timeout of 60 secs" );

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

# check the control URL
my $control = $proxy->control;
ok( $proxy->control_regex eq '(?-xism:^http://proxy(?:/(\w+))?)',
    "Default control regex" );
$proxy->control('control');
ok( $proxy->control_regex eq '(?-xism:^http://control(?:/(\w+))?)',
    "New control regex" );

# check the timeout
$proxy->init;
is( $proxy->agent->timeout, 60, "Default agent timeout of 60 secs" );
is( $proxy->timeout(120), 60, "timeout() returns the old value" );
is( $proxy->agent->timeout, 120, "New agent timeout value of 120 secs" );
