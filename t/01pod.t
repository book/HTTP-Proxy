BEGIN {
    use File::Find;
    use vars qw( @files );

    find( sub { push @files, $File::Find::name if /\.p(?:m|od)$/ },
        'blib/lib' );
}

use Test::More tests => scalar @files;
use Test::Pod;

pod_ok($_) for @files;
