package HTTP::Proxy::Engine::Threaded;
use strict;
use HTTP::Proxy;
use threads;

# A massive hack of Engine::Fork to use the threads stuff
# Basically created to work under win32 so that the filters
# can share global caches among themselves
# Angelos Karageorgiou angelos@unix.gr

our @ISA = qw( HTTP::Proxy::Engine );
our %defaults = (
    max_clients => 60,
);


__PACKAGE__->make_accessors( qw( kids select ), keys %defaults );

sub start {
    my $self = shift;
    $self->kids( [] );
    $self->select( IO::Select->new( $self->proxy->daemon ) );
}

sub run {
    my $self   = shift;
    my $proxy  = $self->proxy;
    my $kids   = $self->kids;

    # check for new connections
    my @ready = $self->select->can_read(1);
    for my $fh (@ready) {    # there's only one, anyway
        # single-process proxy (useful for debugging)

        # accept the new connection
        my $conn  = $fh->accept;
	my $child=threads->new(\&worker,$proxy,$conn);
        if ( !defined $child ) {
            $conn->close;
            $proxy->log( HTTP::Proxy::ERROR, "PROCESS", "Cannot spawn thread" );
            next;
        }
	$child->detach();

    }

}

sub stop {
    my $self = shift;
    my $kids = $self->kids;

   # not needed
}

sub worker {
	my $proxy=shift;
	my $conn=shift;
       $proxy->serve_connections($conn);
	$conn->close();
       return;
}

1;

