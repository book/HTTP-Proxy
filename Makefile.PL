use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'HTTP::Proxy',
    VERSION_FROM => 'lib/HTTP/Proxy.pm',
    PREREQ_PM    => {
        Test::More     => 0,
        HTTP::Daemon   => 1.25,
        LWP::UserAgent => 0,
    },
    ABSTRACT_FROM => 'lib/HTTP/Proxy.pm',
    AUTHOR        => 'Philippe "BooK" Bruhat <book@cpan.org>',
);
