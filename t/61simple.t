use Test::More tests => 6;
use strict;
use HTTP::Proxy::BodyFilter::simple;

my ( $filter, $sub );

# error checking
eval { $filter = HTTP::Proxy::BodyFilter::simple->new("foo") };
like( $@, qr/^Single parameter must be a CODE reference/, "Single coderef" );

eval { $filter = HTTP::Proxy::BodyFilter::simple->new( filter => "foo") };
like( $@, qr/^Parameter to filter must be a CODE reference/, "Need coderef" );

eval { $filter = HTTP::Proxy::BodyFilter::simple->new( filter_file => "foo") };
like( $@, qr/^Parameter to filter must be a CODE reference/, "Need coderef" );

eval { $filter = HTTP::Proxy::BodyFilter::simple->new( typo => sub {} ) };
like( $@, qr/Unkown method typo/, "Incorrect method name" );

$sub = sub {
    my ( $self, $dataref, $message, $protocol, $buffer ) = @_;
    $$dataref =~ s/foo/bar/g;
};

# test the filter
for (
    HTTP::Proxy::BodyFilter::simple->new($sub),
    [ "\nfoo\n", "", "\nbar\n", "" ],
  )
{
    $filter = $_, next if ref $_ eq 'HTTP::Proxy::BodyFilter::simple';

    my ( $data, $buffer ) = @$_[ 0, 1 ];
    $filter->filter( \$data, undef, undef,
        ( defined $buffer ? \$buffer : undef ) );
    is( $data,   $_->[2], "Correct data" );
    is( $buffer, $_->[3], "Correct buffer" );
}

