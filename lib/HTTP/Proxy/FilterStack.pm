package HTTP::Proxy::FilterStack;

use strict;
use Carp;

#
# new( $isbody )
# $isbody is true only for response-body filters stack
sub new {
    my $class = shift;
    my $self  = {
        body => shift || 0,
        filters => [],
        buffers => [],
        current => undef,
    };
    $self->{type} = $self->{body} ? "HTTP::Proxy::BodyFilter"
                                  : "HTTP::Proxy::HeaderFilter";
    return bless $self, $class;
}

#
# insert( $index, [ $matchsub, $filter ], ...)
#
sub insert {
    my ( $self, $idx ) = ( shift, shift );
    $_->[1]->isa( $self->{type} ) or croak("$_ is not a $self->{type}") for @_;
    splice @{ $self->{filters} }, $idx, 0, @_;
}

#
# remove( $index )
#
sub remove {
    my ( $self, $idx ) = @_;
    splice @{ $self->{filters} }, $idx, 1;
}

# 
# push( [ $matchsub, $filter ], ... )
# 
sub push {
    my $self = shift;
    $_->[1]->isa( $self->{type} ) or croak("$_ is not a $self->{type}") for @_;
    push @{ $self->{filters} }, @_;
}

sub all    { return @{ $_[0]->{filters} }; }
sub will_modify { return $_[0]->{will_modify}; }

#
# select the filters that will be used on the message
#
sub select_filters {
    my ($self, $message ) = @_;

    # first time we're called this round
    if ( not defined $self->{current} ) {

        # select the filters that match
        $self->{current} =
          [ map { $_->[1] } grep { $_->[0]->() } @{ $self->{filters} } ];

        # create the buffers
        if ( $self->{body} ) {
            $self->{buffers} = [ ( "" ) x @{ $self->{current} } ];
            $self->{buffers} = [ \( @{ $self->{buffers} } ) ];
        }

        # start the filter if needed (and pass the message)
        for ( @{ $self->{current} } ) {
            if    ( $_->can('begin') ) { $_->begin( $message ); }
            elsif ( $_->can('start') ) {
                $_->proxy->log( HTTP::Proxy::ERROR(), "DEPRECATION", "The start() filter method is *deprecated* and disappeared in 0.15!\nUse begin() in your filters instead!" );
            }
        }

        # compute the "will_modify" value
        $self->{will_modify} = $self->{body}
            ? grep { $_->will_modify() } @{ $self->{current} }
            : 0;
    }
}

#
# the actual filtering is done here
#
sub filter {
    my $self = shift;

    # pass the body data through the filter
    if ( $self->{body} ) {
        my $i = 0;
        my ( $data, $message, $protocol ) = @_;
        for ( @{ $self->{current} } ) {
            $$data = ${ $self->{buffers}[$i] } . $$data;
            ${ $self->{buffers}[ $i ] } = "";
            $_->filter( $data, $message, $protocol, $self->{buffers}[ $i++ ] );
        }
    }
    else {
        $_->filter(@_) for @{ $self->{current} };
        $self->eod;
    }
}

#
# filter what remains in the buffers
#
sub filter_last {
    my $self = shift;
    return unless $self->{body};    # sanity check

    my $i = 0;
    my ( $data, $message, $protocol ) = @_;
    for ( @{ $self->{current} } ) {
        $$data = ${ $self->{buffers}[ $i ] } . $$data;
        ${ $self->{buffers}[ $i++ ] } = "";
        $_->filter( $data, $message, $protocol, undef );
    }

    # call the cleanup routine if needed
    for ( @{ $self->{current} } ) { $_->end if $_->can('end'); }
    
    # clean up the mess for next time
    $self->eod;
}

#
# END OF DATA cleanup method
#
sub eod {
    $_[0]->{buffers} = [];
    $_[0]->{current} = undef;
}

1;

__END__

#
# This is an internal class to work more easily with filter stacks
#
# Here's a description of the class internals
# - filters: the list of (sub, filter) pairs that match the message,
#            and through which it must go
# - current: the actual list of filters, which is computed during
#            the first call to filter()
# - buffers: the buffers associated with each (selected) filter
# - body   : true if it's a HTTP::Proxy::BodyFilter stack
#
# a filter is actually a (matchsub, filterobj) pair
# the matchsub is run againt the HTTP::Message object to find out if
# the filter must be applied to it
