#!/usr/bin/perl -w
use HTTP::Proxy;
use strict;

# a very simple proxy
my $proxy = HTTP::Proxy->new;
$proxy->verbose( shift || 0 );
$proxy->start;