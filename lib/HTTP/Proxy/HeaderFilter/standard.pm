package HTTP::Proxy::HeaderFilter::standard;

use strict;
use HTTP::Proxy;
use HTTP::Headers::Util qw( split_header_words );
use base qw( HTTP::Proxy::HeaderFilter );

# known hop-by-hop headers
my %hopbyhop = map { $_ => 1 }
  qw( Connection Keep-Alive Proxy-Authenticate Proxy-Authorization
      TE Trailers Transfer-Encoding Upgrade Proxy-Connection Public );

# standard proxy header filter (RFC 2616)
sub filter {
    my ( $self, $headers, $message ) = @_;

    # the Via: header
    my $via = $message->protocol() || '';
    if ( $self->proxy->via and $via =~ s!HTTP/!! ) {
        $via .= " " . $self->proxy->via;
        $headers->header(
            Via => join ', ',
            $message->headers->header('Via') || (), $via
        );
    }

    # the X-Forwarded-For header
    $headers->push_header(
        X_Forwarded_For => $self->proxy->client_socket->peerhost )
      if $self->proxy->x_forwarded_for;

    # make a list of hop-by-hop headers
    my %h2h = %hopbyhop;
    my $hop = HTTP::Headers->new();
    $h2h{ $_->[0] } = 1
      for map { split_header_words($_) } $headers->header('Connection');

    # hop-by-hop headers are set aside
    $headers->scan(
        sub {
            my ( $k, $v ) = @_;
            if ( $h2h{$k} ) {
                $hop->push_header( $k => $v );
                $headers->remove_header($k);
            }
        }
    );

    # set the hop-by-hop headers in the proxy
    # only the end-to-end headers are left in the message
    $self->proxy->hop_headers($hop);

    # handle Max-Forwards
    if ( $message->isa('HTTP::Request')
        and defined $headers->header('Max-Forwards') ) {
        my ( $max, $method ) =
          ( $headers->header('Max-Forwards'), $message->method );
        if ( $max == 0 ) {
            # answer directly TRACE ou OPTIONS
            if ( $method eq 'TRACE' ) {
                my $response =
                  HTTP::Response->new( 200, 'OK',
                    HTTP::Headers->new( Content_Type => 'message/http'
                    , Content_Length => 0),
                    $message->as_string );
                $self->proxy->response($response);
            }
            elsif ( $method eq 'OPTIONS' ) {
                my $response = HTTP::Response->new(200);
                $response->header( Allow => join ', ', @HTTP::Proxy::METHODS );
                $self->proxy->response($response);
            }
        }
        # The Max-Forwards header field MAY be ignored for all
        # other methods defined by this specification (RFC 2616)
        elsif ( $method =~ /^(?:TRACE|OPTIONS)/ ) {
            $headers->header( 'Max-Forwards' => --$max );
        }
    }

    # remove some headers
    $headers->remove_header($_) for (

        # LWP::UserAgent Client-* headers
        qw( Client-Aborted Client-Bad-Header-Line Client-Date Client-Junk
        Client-Peer Client-Request-Num Client-Response-Num
        Client-SSL-Cert-Issuer Client-SSL-Cert-Subject Client-SSL-Cipher
        Client-SSL-Warning Client-Transfer-Encoding Client-Warning ),

        # no encoding accepted (gzip, compress, deflate)
        qw( Accept-Encoding ),
    );
}

1;

__END__

=head1 NAME

HTTP::Proxy::HeaderFilter::standard - An internal filter to respect RFC2616

=head1 DESCRIPTION

This is an internal filter used by HTTP::Proxy.

Move along, nothing to see here.

=head1 AUTHOR

Philippe "BooK" Bruhat, E<lt>book@cpan.orgE<gt>.

Thanks to Gisle Aas, for directions regarding the handling of the
hop-by-hop headers.

=head1 COPYRIGHT

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

