use strict;
use Test::More tests => 6;
use HTTP::Proxy;

# test the basic filter methods
my $proxy = HTTP::Proxy->new( port => 0 );

# test the errors
eval {
    $proxy->_push_filter( response => sub { } );
};
like( $@, qr/No filter type/, "Miscall of an internal method" );

eval {
    $proxy->push_headers_filter( typo => sub { } );
};
like( $@, qr/No message type/, "Unknown filter stack" );

eval { $proxy->push_body_filter( response => 'code' ) };
like( $@, qr/Not a CODE reference/, "Wasn't given a code reference" );

eval {
    $proxy->push_body_filter( mime => 'text', response => sub { } );
};
like( $@, qr/Invalid MIME/, "Bad MIME type" );

# test the various internal subs
my $request = HTTP::Request->new( GET => 'http://www.perl.org/' );
my $response = HTTP::Response->new;
my @filters;
$proxy->request($request);
$proxy->response($response);

# defaults for push_xxx_filter are:
#    mime   => 'text/*'
#    method => 'GET, POST, HEAD'
#    scheme => 'http'
#    host   => ''
#    path   => ''

$response->headers->header( Content_type => 'text/plain' );

$proxy->push_body_filter( response => sub { } );
@filters = $proxy->_filter_select( response => 'body' );
is( @filters, 1, "The filter matches the response" );

$proxy->push_headers_filter( request => sub { }, host => qr/perl\.org/i );
$proxy->push_headers_filter( request => sub { }, host => qr/perl/i );
$proxy->push_headers_filter( request => sub { }, host => qr/java/ );
@filters = $proxy->_filter_select( request => 'headers' );

# there is one default header filter for the proxy
is( @filters, 3, "The filter matches the request" );

