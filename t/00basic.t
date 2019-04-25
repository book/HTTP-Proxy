use vars qw( @modules );

BEGIN {
    use Config;
    use File::Find;
    use vars qw( @modules );
    my $dir = -e 'blib/lib' ? 'blib/lib' : 'lib';
    find( sub { push @modules, $File::Find::name if /\.pm$/ }, $dir );
}

use Test::More tests => scalar @modules;

for ( sort map { s!/!::!g; s/\.pm$//; s/^(?:blib::)?lib:://; $_ } @modules ) {
SKIP:
    {
        skip "$^X is not a threaded Perl", 1
            if /Thread/ && !$Config{usethreads};
        use_ok($_);
    }
}

