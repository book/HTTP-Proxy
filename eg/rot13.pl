#!/usr/bin/perl -w
use HTTP::Proxy qw( :log );
use HTTP::Proxy::BodyFilter::tags;
use HTTP::Proxy::BodyFilter::htmltext;
use strict;

my $proxy = HTTP::Proxy->new( port => 8080 );
$proxy->logmask( shift || NONE );

$proxy->push_filter(
    mime     => 'text/html',
    response => HTTP::Proxy::BodyFilter::tags->new,
    response =>
      HTTP::Proxy::BodyFilter::htmltext->new( sub { tr/a-zA-z/n-za-mN-ZA-M/ } )
);

$proxy->start;

