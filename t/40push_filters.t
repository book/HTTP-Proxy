use strict;
use Test::More tests => 3;
use HTTP::Proxy;

# test the basic filter methods
my $proxy = HTTP::Proxy->new( port => 0 );

# test the errors
eval {
    $proxy->push_filter( response => 1 );
};
like( $@, qr/Not a Filter reference for filter queue/, "Bad parameter" );

eval {
    $proxy->push_filter( typo => sub { } );
};
like( $@, qr/No message type/, "Unknown filter stack" );

eval {
    $proxy->push_filter( mime => 'text', response => sub { } );
};
like( $@, qr/Invalid MIME/, "Bad MIME type" );

