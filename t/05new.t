use Test::More tests => 10;

use HTTP::Proxy;

my $proxy;

$proxy = HTTP::Proxy->new;

# check for defaults
is( $proxy->port,    8080,        'Default port' );
is( $proxy->verbose, 0,           'Default verbosity' );
is( $proxy->host,    'localhost', 'Default host' );
is( $proxy->agent, undef, 'Default agent' );

# new with arguments
$proxy = HTTP::Proxy->new(
    port    => 3128,
    host    => 'foo',
    verbose => 1,
);

is( $proxy->port,    3128,  'port set by new' );
is( $proxy->verbose, 1,     'verbosity set by new' );
is( $proxy->host,    'foo', 'host set by new' );

# check the accessors
is( $proxy->verbose(0), 1, 'port accessor' );
is( $proxy->verbose, 0, 'port changed by accessor' );

# check a read-only accessor
my $conn = $proxy->conn;
$proxy->conn($conn + 100);
is( $proxy->conn, $conn, 'read-only attribute' );

