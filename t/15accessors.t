use Test::More tests => 26;
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
    maxchild        => 10,
    maxconn         => 0,
    maxserve        => 10,
    port            => 8080,
    request         => undef,
    response        => undef,
    hop_headers     => undef,
    logmask         => 0,
    x_forwarded_for => 1,
    conn            => 0,
    client_socket   => undef,
    # control_regex, loop are not used/internal for now
);

for my $key ( sort keys %meth ) {
    no strict 'refs';
    is( $proxy->$key(), $meth{$key}, "$key has the correct default" );
}

like( $proxy->via(), qr!\(HTTP::Proxy/$HTTP::Proxy::VERSION\)$!,
      "via has the correct default");

#
# test generated accessors (they're all the same)
#

is( $proxy->port(8888), $meth{port}, "Set return the previous value" );
is( $proxy->port, 8888, "Set works" );

#
# other accessors
#

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
$proxy->_init_agent;
is( $proxy->agent->timeout, 60, "Default agent timeout of 60 secs" );
is( $proxy->timeout(120), 60, "timeout() returns the old value" );
is( $proxy->agent->timeout, 120, "New agent timeout value of 120 secs" );
