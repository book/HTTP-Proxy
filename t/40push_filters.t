use strict;
use Test::More tests => 5;
use HTTP::Proxy;
use HTTP::Proxy::HeaderFilter;

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

# test correct working
my $filter = HTTP::Proxy::HeaderFilter->new;
eval {
    $proxy->push_filter( response => $filter );
};
is( $@, '', "Accept a HeaderFilter");

{
  package Foo;
  use base qw( HTTP::Proxy::HeaderFilter );
}
$filter = Foo->new;
eval {
    $proxy->push_filter( response => $filter );
};
is( $@, '', "Accept an object derived from  HeaderFilter");

