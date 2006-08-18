use strict;
use Test::More tests => 2;
use HTTP::Proxy;
use HTTP::Proxy::BodyFilter::tags;
use HTTP::Proxy::BodyFilter::simple;
use HTTP::Proxy::BodyFilter::complete;
use HTTP::Request;

my $proxy = HTTP::Proxy->new( port => 0 );

my $req = HTTP::Request->new( GET => 'http://www.zlonk.com/' );
my $res = HTTP::Response->new();
$res->request( $req );
$res->content_type( 'text/html' );
$proxy->request( $req );
$proxy->response( $res );

# filters that don't modify anything
$proxy->push_filter(
    host     => 'zlonk.com',
    response => HTTP::Proxy::BodyFilter::tags->new(),
    response => HTTP::Proxy::BodyFilter::complete->new(),
);

$proxy->{body}{response}->select_filters( $res );
ok( !$proxy->{body}{response}->will_modify(),
    q{Filters won't change a thing}
);

# simulate end of connection
$proxy->{body}{response}->eod();

# add a filter that will change stuff
$proxy->push_filter(
    host     => 'zlonk.com',
    response => HTTP::Proxy::BodyFilter::simple->new( sub {} ),
);

$proxy->{body}{response}->select_filters( $res );
ok( $proxy->{body}{response}->will_modify( $res ),
    q{Filters admit they will change something}
);
