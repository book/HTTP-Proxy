use Test::More tests => 2;
use strict;
use HTTP::Proxy;
use HTTP::Proxy::BodyFilter::simple;
use t::Utils;

# create the filter
my $sub = sub {
    my ( $self, $dataref, $message, $protocol, $buffer ) = @_;
    $$dataref =~ s/test/foo/g;
};

my $filter = HTTP::Proxy::BodyFilter::simple->new($sub);

# create the proxy
my $proxy = HTTP::Proxy->new(
    port     => 0,
    maxchild => 0,
    maxserve => 1,
    maxconn  => 1,
);
$proxy->init;
$proxy->agent->protocols_allowed(undef);
$proxy->push_filter( response => $filter, scheme => 'file', mime => 'text/*' );
my $url = $proxy->url;

# fork the proxy
my @pids;
push @pids, fork_proxy($proxy);

# check that the correct transformation is applied
my $ua = LWP::UserAgent->new();
$ua->proxy( file => $url );
my $response = $ua->request( HTTP::Request->new( GET => 'file:t/test.html' ) );

my $file;
{
    local $/ = undef;
    open F, "t/test.html" or diag "Unable to open t/test.html";
    $file = <F>;
    close F;
}
$file =~ s/test/foo/g;
is( $response->content, $file, "The proxy applied the transformation" );

# push another filter
$sub = sub {
    my ( $self, $dataref, $message, $protocol, $buffer ) = @_;
    $$dataref =~ s/Test/Bar/g;
};
$filter = HTTP::Proxy::BodyFilter::simple->new($sub);
$proxy->push_filter( response => $filter, scheme => 'file', mime => 'text/*' );

# fork the modified proxy
push @pids, fork_proxy($proxy);

$response = $ua->request( HTTP::Request->new( GET => 'file:t/test.html' ) );
$file =~ s/Test/Bar/g;
is( $response->content, $file, "The proxy applied two transformations" );

# wait for kids
wait for @pids;

