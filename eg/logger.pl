#!/usr/bin/perl -w
use strict;
use HTTP::Proxy qw( :log );
use HTTP::Proxy::HeaderFilter::simple;
use HTTP::Proxy::BodyFilter::simple;
use CGI::Util qw( unescape );

my @srv_hdr = qw( Content-Type Set-Cookie Set-Cookie2 WWW-Authenticate
                  Location );
my @clt_hdr = qw( Cookie Cookie2 Referer Referrer Authorization );

# NOTE: Body request filters always receive the request body in one pass
my $post_filter = HTTP::Proxy::BodyFilter::simple->new(
    sub {
        my ( $self, $dataref, $message, $protocol, $buffer ) = @_;
        print STDOUT $message->method, " ", $message->uri, "\n";
        print_headers( $message, @clt_hdr);

        # this is from CGI.pm, method parse_params
        my (@pairs) = split ( /[&;]/, $$dataref );
        for (@pairs) {
            my ( $param, $value ) = split ( '=', $_, 2 );
            $param = unescape($param);
            $value = unescape($value);
            printf STDOUT "    %-30s => %s\n", $param, $value;
        }
    }
);

my $get_filter = HTTP::Proxy::HeaderFilter::simple->new(
    sub {
        my ( $self, $headers, $message ) = @_;
        my $req = $message->request;
        if( $req->method ne 'POST' ) {
            print STDOUT $req->method, " ", $req->uri, "\n";
            print_headers( $req, @clt_hdr);
        }
        print STDOUT "    ", $message->status_line, "\n";
        print_headers( $message, @srv_hdr );
    }
);

sub print_headers {
    my $message = shift;
    for my $h (@_) {
        if( $message->header($h) ) {
            print STDOUT "    $h: $_\n" for ( $message->header($h) );
        }
    }
}

my $proxy = HTTP::Proxy->new;
$proxy->logmask( shift || NONE );
$proxy->push_filter( method => 'POST', request => $post_filter );
$proxy->push_filter( response => $get_filter );
$proxy->start;

