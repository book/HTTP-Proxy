package HTTP::Proxy::HeaderFilter::standard;

use strict;
use HTTP::Proxy;
use Sys::Hostname;
use base qw( HTTP::Proxy::HeaderFilter );

my $VIA = " " . hostname() . " (HTTP::Proxy/$HTTP::Proxy::VERSION)";

# standard proxy header filter (RFC 2616)
sub filter {
    my ( $self, $headers, $message ) = @_;

    # the Via: header
    my $via = $message->protocol() || '';
    if ( $via =~ s!HTTP/!! ) {
        $via .= $VIA;
        $message->headers->header(
            Via => join ', ',
            $message->headers->header('Via') || (), $via
        );
    }

    # remove some headers
    for (

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
    {
        $message->headers->remove_header($_);
    }
}

1;
