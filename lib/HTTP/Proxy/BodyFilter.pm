package HTTP::Proxy::BodyFilter;

use Carp;

=head1 NAME

HTTP::Proxy::BodyFilter - A base class for HTTP messages body filters

=head1 SYNOPSIS

    package MyFilter;

    use base qw( HTTP::Proxy::BodyFilter );

    # a simple modification, that may break things
    sub filter {
        my ( $self, $dataref, $message, $protocol, $buffer ) = @_;
        $$dataref =~ s/PERL/Perl/g;
    }
    
    1;

=head1 DESCRIPTION

The HTTP::Proxy::BodyFilter class is used to create filters for
HTTP request/response body data.

=cut

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->init(@_) if $self->can('init');
    return $self;
}

=head2 Creating a BodyFilter

A BodyFilter is just a derived class that implements the filter()
method. See the example in L<SYNOPSIS>.

The signature of the filter() method is the following:

    sub filter {
        my ( $self, $dataref, $message, $protocol, $buffer ) = @_;
        ...
    }

where $self is the filter object, $dataref is a reference to the chunk
of body data received, $headers is a reference to  HTTP::Headers object,
$message is a reference to either a HTTP::Request or a HTTP::Response
object, and $protocol is a reference to the LWP::Protocol protocol object.

Note that this subroutine signature looks a lot like that of the call-
backs of LWP::UserAgent (except that $message is either a HTTP::Request
or a HTTP::Response object).

$buffer is a reference to a buffer where some of the unprocessed data
can be stored for the next time the filter will be called (see L<Using
a buffer to store data for a later use> for details). Thanks to the
built-in HTTP::Proxy::BodyFilter::* filters, this is rarely needed.

The $headers HTTP::Headers object is the one that was sent to the client
(if the filter is on the response stack) or origin server (if the filter
is on the request stack). Modifying it in the filter() method is useless,
since the headers have already been sent.

=head2 Using a buffer to store data for a later use

FIXME

=head2 The store and forward approach

HTTP::Proxy implements a I<store and forward> mechanism, for those
filters who needs to have the whole (response) message body to
work. It's simply enabled by pushing the HTTP::Proxy::BodyFilter::store
filter on the filter stack.

Filters that need to have access to all the data can implement the
filter_file() method, that is only called when there was a
HTTP::Proxy::BodyFilter::store filter earlier in the chain.
Its signature is:

    sub filter_file { my ( $self, $filename, $message, $protocol ) = @_; ... }

If they require to have the whole file, they usually shouldn't implement
the filter() method. Calling such a filter outside the store and foward
mechanisme will then cause a runtime error.

In the store and forward mechanism, $headers is I<still> modifiable by
the filter, and the modified headers will be sent to the client or server.

=head2 Standard BodyFilters

Standard HTTP::Proxy::BodyFilter classes are lowercase.

The following BodyFilters are included in the HTTP::Proxy distribution:

=over 4

=item lines

This filter makes sure that the next filter in the filter chain will
only receive complete lines. The "chunks" of data received by the
following filters with either end with C<\n> or will be the last
piece of data for the current HTTP message body.

=item log

This filter allows logging based on the HTTP message body data.

=item store (TODO)

This filter stores the page in a temporary file, thus allowing
some actions to be taken only when the full page has been received
by the proxy.

The interface is not completely defined yet.

=back

=cut

sub filter {
    croak "HTTP::Proxy::HeaderFilter cannot be used as a filter";
}

=head1 AUTHOR

Philippe "BooK" Bruhat, E<lt>book@cpan.orgE<gt>.

=head1 SEE ALSO

HTTP::Proxy, HTTP::Proxy::HeaderFilter.

=head1 COPYRIGHT

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

1;
