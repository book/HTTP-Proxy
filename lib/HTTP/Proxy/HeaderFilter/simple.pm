package HTTP::Proxy::HeaderFilter::simple;

use strict;
use Carp;
use base qw( HTTP::Proxy::HeaderFilter );

=head1 NAME

HTTP::Proxy::HeaderFilter::simple - A class for creating simple filters

=head1 SYNOPSIS

    use HTTP::Proxy::HeaderFilter::simple;

    # a simple User-Agent filter
    my $filter = HTTP::Proxy::HeaderFilter::simple->new(
        sub { $_[0]->header( User_Agent => 'foobar/1.0' ); }
    );
    $proxy->push_filter( request => $filter );

=head1 DESCRIPTION

HTTP::Proxy::HeaderFilter::simple can create BodyFilter without going
through the hassle of creating a full-fledged class. Simply pass
a code reference to the filter() method of your filter to the constructor,
and you'll get the adequate filter.

=head2 Constructor calling convention

The constructor is called with a single code reference.
The code reference must conform to the standard filter() signature
for header filters:

    sub filter { my ( $headers, $message) = @_; ... }

This code reference is used for the filter() method.

=cut

sub init {
    my $self = shift;
    $self->{filter} = \&HTTP::Proxy::HeaderFilter::filter;

    croak "Parameter must be a CODE reference" unless ref $_[0] eq 'CODE';
    $self->{filter} = $_[0];
}

# transparently call the actual filter() method
sub filter      { goto &{ $_[0]{filter} }; }

=head1 AUTHOR

Philippe "BooK" Bruhat, E<lt>book@cpan.orgE<gt>.

=head1 COPYRIGHT

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

1;
