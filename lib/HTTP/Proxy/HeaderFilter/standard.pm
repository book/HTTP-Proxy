package HTTP::Proxy::HeaderFilter::standard;

use strict;
use HTTP::Proxy;
use base qw( HTTP::Proxy::HeaderFilter );

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

    # remove some headers
    $headers->remove_header($_) for (

        # LWP::UserAgent Client-* headers
        qw( Client-Aborted Client-Bad-Header-Line Client-Date Client-Junk
        Client-Peer Client-Request-Num Client-Response-Num
        Client-SSL-Cert-Issuer Client-SSL-Cert-Subject Client-SSL-Cipher
        Client-SSL-Warning Client-Transfer-Encoding Client-Warning ),

        # hop-by-hop headers (for now)
        qw( Connection Keep-Alive TE Trailers Transfer-Encoding Upgrade
        Proxy-Connection Proxy-Authenticate Proxy-Authorization Public ),

        # no encoding accepted (gzip, compress, deflate)
        qw( Accept-Encoding ),
      )
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

=head1 COPYRIGHT

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

