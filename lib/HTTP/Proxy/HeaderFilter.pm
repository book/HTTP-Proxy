package HTTP::Proxy::HeaderFilter;

use Carp;

=head1 NAME

HTTP::Proxy::HeaderFilter - A base class for HTTP message header filters

=head1 SYNOPSIS

    package MyFilter;

    use base qw( HTTP::Proxy::HeaderFilter );

    # changes the User-Agent header in all requests
    # this filter must be pushed on the request stack
    sub filter {
        my ( $self, $headers, $message ) = @_;

        $message->headers->header( User_Agent => 'MyFilter/1.0' );
    }
    
    1;

=head1 DESCRIPTION

The HTTP::Proxy::HeaderFilter class is used to create filters for
HTTP request/response headers.

=cut

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->init(@_) if $self->can('init');
    return $self;
}

=head2 Creating a HeaderFilter

A HeaderFilter is just a derived class that implements the filter()
method. See the example in L<SYNOPSIS>.

The signature of the filter() method is the following:

    sub filter { my ( $self, $headers, $message) = @_; ... }

where $self is the filter object, $headers is a HTTP::Headers object,
and $message is either a HTTP::Request or a HTTP::Response object.

The $headers HTTP::Headers object is the one that will be sent to
the client (if the filter is on the response stack) or origin
server (if the filter is on the request stack). If $headers is
modified by the filter, the modified headers will be sent to the
client or server.

=head2 Standard HeaderFilters

Standard HTTP::Proxy::HeaderFilter classes are lowercase.

The following HeaderFilters are included in the HTTP::Proxy distribution:

=over 4

=item log

This filter allows logging based on the HTTP message headers.

=item standard

This is the filter that provides standard headers handling for HTTP::Proxy.
It is loaded automacally by HTTP::Proxy.

=back

=cut

sub filter {
    croak "HTTP::Proxy::HeaderFilter cannot be used as a filter";
}

=head1 AUTHOR

Philippe "BooK" Bruhat, E<lt>book@cpan.orgE<gt>.

=head1 SEE ALSO

HTTP::Proxy, HTTP::Proxy::BodyFilter.

=head1 COPYRIGHT

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

1;
