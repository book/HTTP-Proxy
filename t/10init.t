use Test::More tests => 6;

use HTTP::Proxy;

my ( $proxy, $agent, $daemon );

# individual methods
$proxy = HTTP::Proxy->new;
is( $proxy->agent,  undef, 'agent undefined at startup' );
is( $proxy->daemon, undef, 'daemon undefined at startup' );

# private methods (should we test them?)
$agent  = $proxy->_init_agent;
$daemon = $proxy->_init_daemon;
isa_ok( $agent,  'LWP::UserAgent', 'init_agent' );
isa_ok( $daemon, 'HTTP::Daemon',   'init_daemon' );

# this is ugly
$daemon = undef;

# combined init method
$proxy = HTTP::Proxy->new;
$agent = $proxy->init;
isa_ok( $proxy->agent,  'LWP::UserAgent', 'init agent' );
isa_ok( $proxy->daemon, 'HTTP::Daemon',   'init daemon' );
