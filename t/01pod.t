BEGIN {
    use File::Find;
    use vars qw( @files );

    find( sub { push @files, $File::Find::name if /\.p(?:m|od)$/ },
        'blib/lib' );
}

use Test::More tests => scalar @files;

SKIP: {
    eval { require Test::Pod; import Test::Pod; };
    skip "Test::Pod not available", scalar @files if $@;
    pod_ok($_) for @files;
}

