use Test::More tests => 3;
use strict;
use HTTP::Proxy::HeaderFilter::simple;
use HTTP::Headers;

my ( $filter, $sub, $h );

# error checking
eval { $filter = HTTP::Proxy::HeaderFilter::simple->new() };
like( $@, qr/^Parameter must be a CODE reference/, "Must pass a coderef" );

eval { $filter = HTTP::Proxy::HeaderFilter::simple->new('foo') };
like( $@, qr/^Parameter must be a CODE reference/, "Must pass a coderef" );

$sub = sub {
    my ( $self, $headers, $message ) = @_;
    $headers->header( User_Agent => 'Foo/1.0' );
};

$filter = HTTP::Proxy::HeaderFilter::simple->new( $sub );

# test the filter
$h = HTTP::Headers->new(
    Date         => 'Thu, 03 Feb 1994 00:00:00 GMT',
    Content_Type => 'text/html; version=3.2',
    Content_Base => 'http://www.perl.org/'
);

$filter->filter( $h, undef );
is( $h->header( 'User-Agent' ), 'Foo/1.0', "Header modified" );

