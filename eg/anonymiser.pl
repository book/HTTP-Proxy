#!/usr/bin/perl -w
# yeah, I know, I write UK English ;-) 
use HTTP::Proxy qw( :log );
use strict;

# a very simple proxy
my $proxy = HTTP::Proxy->new;
$proxy->logmask( shift || NONE );

# the anonymising filter
$proxy->push_headers_filter(
    mime    => undef,
    request => sub {
        $_[0]->remove_header(qw( User-Agent From Referer Cookie ));
    },
    response => sub {
        $_[0]->remove_header(qw( Set-Cookie )),;
    },
);

$proxy->start;
