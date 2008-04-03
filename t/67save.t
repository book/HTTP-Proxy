use strict;
use warnings;
use Test::More;
use HTTP::Proxy::BodyFilter::save;
use File::Temp qw( tempdir );

# a sandbox to play in
my $dir = tempdir( CLEANUP => 1 );

my @errors = (
    [   [ keep_old => 1, timestamp => 1 ] =>
            qr/^Can't timestamp and keep older files at the same time/
    ],
    [ [ status => 200 ] => qr/^status must be an array reference/ ],
    [   [ status => [qw(200 007 )] ] =>
            qr/status must contain only HTTP codes/
    ],
    [ [ filename => 'zlonk' ] => qr/^filename must be a code reference/ ],
);
my @data = (
    'recusandae veritatis illum quos tempor aut quidem',
    'necessitatibus lorem aperiam facere consequuntur incididunt similique'
);

plan tests => 2 * @errors + 1 + 6 * @data;

# some variables
my $proxy = HTTP::Proxy->new( port => 0 );
my ( $filter, $req, $res, $data, $file, $buffer, $fh );

# test the save filter
# 1) errors in new
for my $t (@errors) {
    my ( $args, $regex ) = @$t;
    ok( !eval { HTTP::Proxy::BodyFilter::save->new(@$args); 1; },
        "new( @$args ) fails" );
    like( $@, $regex, "Error matches $regex" );
}

# 2) code for filenames
$filter = HTTP::Proxy::BodyFilter::save->new( filename => sub {$file} );
$filter->proxy($proxy);

# simple check
ok( !$filter->will_modify, 'Filter does not modify content' );

# loop on two requests
for my $name (qw( zlonk.pod kayo.html )) {
    $file = "$dir/$name";

    $req = HTTP::Request->new();
    ok( eval {
            $filter->begin($req);
            1;
        },
        'Initialized filter without error'
    );
    is( $filter->{_hpbf_save_filename}, $file, "Got filename $file" );
    ok( $filter->{_hpbf_save_fh}->opened, 'Filehandle opened' );

    # add some data

    $buffer = '';
    ok( eval {
            $filter->filter( \$data[0], $req, '', \$buffer );
            $filter->filter( \$data[1], $req, '', undef );
            $filter->end();
            1;
        },
        'Filtered data without error'
    );

    # file closed now
    ok( !$filter->{_hpbf_save_fh}->opened, 'Filehandle closed' );

    # check the data
    open $fh, $file or diag "Can't open $file: $!";
    is( join( '', <$fh> ), join( '', @data ), 'All data saved' );
    close $fh;

}

# 3) multiple calls to the same filter
# 4) the multiple templating cases

