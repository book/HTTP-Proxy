BEGIN {
    use File::Find;
    use vars qw( @files );

    find( sub { push @files, $File::Find::name if /\.p(?:m|od)$/ },
        'blib/lib' );
}

use Test::More tests => scalar @files;

SKIP: {
    eval { require Test::Pod };
    skip "Test::Pod not available", 1 if $@;
    pod_ok($_) for @files;
}

