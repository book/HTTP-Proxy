package HTTP::Proxy;

use HTTP::Daemon;
use Carp;

use strict;
use vars qw( $VERSION $AUTOLOAD );

$VERSION = 0.01;

=pod

=head1 NAME

HTTP::Proxy - A pure Perl HTTP proxy

=head1 SYNOPSIS

    use HTTP::Proxy;

    # initialisation
    my $proxy = HTTP::Proxy->new( port =>

    # alternate initialisation
    my $proxy = HTTP::Proxy->new;
    $proxy->port( 8080 ); # the classical accessors are here!
    
    # this is a MainLoop-like method
    $proxy->start;

=head1 DESCRIPTION


=head1 METHODS

=head2 Constructor

=cut

sub new {
    my $class = shift;

    # some defaults
    return bless {
        host    => 'localhost',
        port    => 8080,
        agent   => undef,
        verbose => 0,
        @_,
    }, $class;
}

=head2 Accessors

The HTTP::Proxy has several accessors. They are all AUTOLOADed,
and read-write. Called with arguments, the accessor returns the
current value. Called with a single argument, it set the current
value and returns the previous one, in case you want to keep it.

=cut

sub AUTOLOAD {

    # we don't DESTROY
    return if $AUTOLOAD =~ /::DESTROY/;

    # fetch the attribute name
    $AUTOLOAD =~ /.*::(\w+)/;
    my $attr = $1;

    # must be one of the registered subs
    if ( $attr =~ /^(?:agent|host|port|verbose)$/x ) {
        no strict 'refs';

        # get the real attribute name
        $attr =~ s/^[gs]et_//;

        # create and register the method
        *{$AUTOLOAD} = sub {
            my $self = shift;
	    my $old = $self->{$attr};
            $self->{$attr} = shift if @_;
	    return $old;
        };

        # now do it
        goto &{$AUTOLOAD};
    }
    croak "Undefined method $AUTOLOAD";
}

=head2 Callbacks

=cut

1;
