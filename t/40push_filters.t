use strict;
use Test::More tests => 4;
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

