use ExtUtils::MakeMaker;
WriteMakefile(
	NAME          => 'HTTP::Proxy',
	VERSION_FROM  => 'lib/HTTP/Proxy.pm',
	PREREQ_PM     => { },
	ABSTRACT_FROM => 'lib/HTTP/Proxy.pm',
	AUTHOR        => 'Philippe "BooK" Bruhat <book@cpan.org>',
);
