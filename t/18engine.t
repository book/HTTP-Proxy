use Test::More;
use HTTP::Proxy::Engine;

plan tests => 19;

my $e;
my $p = bless {}, "HTTP::Proxy";

$e = HTTP::Proxy::Engine->new( proxy => $p, engine => Vintage );
isa_ok( $e, 'HTTP::Proxy::Engine::Vintage' );

# use the default engine for $^O
eval { HTTP::Proxy::Engine->new() };
isa_ok( $e, 'HTTP::Proxy::Engine' );

eval { HTTP::Proxy::Engine->new( engine => Vintage ) };
like( $@, qr/^No proxy defined/, "proxy required" );

eval { HTTP::Proxy::Engine->new( proxy => "P", engine => Vintage ) };
like( $@, qr/^P is not a HTTP::Proxy object/, "REAL proxy required" );

# direct engine creation
# HTTP::Proxy::Engine::Vintage was required before
$e = HTTP::Proxy::Engine::Vintage->new( proxy => $p );
isa_ok( $e, 'HTTP::Proxy::Engine::Vintage' );

eval { HTTP::Proxy::Engine::Vintage->new() };
like( $@, qr/^No proxy defined/, "proxy required" );

eval { HTTP::Proxy::Engine::Vintage->new( proxy => "P" ) };
like( $@, qr/^P is not a HTTP::Proxy object/, "REAL proxy required" );

# non-existent engine
eval { HTTP::Proxy::Engine->new( proxy => $p, engine => Bonk ) };
like(
    $@,
    qr/^Can't locate HTTP.+?Proxy.+?Engine.+?Bonk\.pm in \@INC/,
    "Engine Bonk does not exist"
);

# check the base accessor
$e = HTTP::Proxy::Engine->new( proxy => $p, engine => Vintage );
is( $e->proxy, $p, "proxy() get" );

$e->proxy("P");
is( $e->proxy, "P", "proxy() set" );

# check subclasses accessors
$e =
  HTTP::Proxy::Engine->new( proxy => $p, engine => Vintage, max_clients => 2 );
is( $e->max_clients,    2, "subclass get()" );
is( $e->max_clients(4), 4, "subclass set()" );
is( $e->max_clients,    4, "subclass get()" );

$e = HTTP::Proxy::Engine::Vintage->new( proxy => $p, max_clients => 3 );
is( $e->max_clients,    3, "subclass get()" );
is( $e->max_clients(4), 4, "subclass set()" );
is( $e->max_clients,    4, "subclass get()" );

# but where is the code?
is( *{HTTP::Proxy::Engine::max_clients}{CODE},
    undef, "code not in the base class" );
is( ref *{HTTP::Proxy::Engine::max_clients}{CODE},
    '', "code not in the base class" );
is( ref *{HTTP::Proxy::Engine::Vintage::max_clients}{CODE},
    'CODE', "code in the subclass" );

