package HTTP::Proxy::BodyFilter::tags;

use strict;
use Carp;
use base qw( HTTP::Proxy::BodyFilter );

=head1 NAME

HTTP::Proxy::BodyFilter::tags - A filter that outputs only complete tags

=head1 SYNOPSIS

    use HTTP::Proxy::BodyFilter::tags;
    use MyFilter;    # this filter only works on complete tags

    my $filter = MyFilter->new();

    # note that both filters will be run on the same messages
    # (those with a MIME type of text/html)
    $proxy->push_filter(
        mime     => 'text/*',
        response => HTTP::Proxy::BodyFilter::tags->new
    );
    $proxy->push_filter( mime => 'text/html', response => $filter );

=head1 DESCRIPTION

The HTTP::Proxy::BodyFilter::tags filter makes sure that the next filter
in the filter chain will only receive complete tags.

=cut

sub filter {
    my ( $self, $dataref, $message, $protocol, $buffer ) = @_;
    return if not defined $buffer;    # last "tags"

    my $idx = rindex( $$dataref, '<' );
    if ( $idx > rindex( $$dataref, '>' ) ) {
        $$buffer = substr( $$dataref, $idx );
        $$dataref = substr( $$dataref, 0, $idx );
    }
}

=head1 AUTHOR

Philippe "BooK" Bruhat, E<lt>book@cpan.orgE<gt>.

=head1 COPYRIGHT

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

1;
