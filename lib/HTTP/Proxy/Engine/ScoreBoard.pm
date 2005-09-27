package HTTP::Proxy::Engine::ScoreBoard;
use strict;
use POSIX ":sys_wait_h";    # WNOHANG
use Fcntl qw(LOCK_UN LOCK_EX);
use IO::Handle;
use HTTP::Proxy;

our @ISA = qw( HTTP::Proxy::Engine );
our %defaults = (
    start_servers          => 4,      # start this many, and don't go below
    max_clients            => 12,     # don't go above
    max_requests_per_child => 250,    # just in case there's a leak
    min_spare_servers      => 1,      # minimum idle (if 0, never start new)
    max_spare_servers => 12,    # maximum idle (should be "single browser max")
    verify_delay      => 60,    # minimum time between kids verification
);

__PACKAGE__->make_accessors(
    qw(
      kids select status_read status_write scoreboard
      verify_live_kids_time last_active_time last_fork_time
      ),
    keys %defaults
);

sub start {
    my $self = shift;
    $self->kids( {} );

    # set up the communication pipe
    $self->status_read( IO::Handle->new() );
    $self->status_write( IO::Handle->new() );
    pipe( $self->status_read(), $self->status_write() )
      or die "Can't create pipe: $!";
    $self->status_write()->autoflush(1);
    $self->select( IO::Select->new( $self->status_read() ) );
    setpgrp;    # set as group leader

    # scoreboard information
    $self->verify_live_kids_time( time );
    $self->last_active_time( time );
    $self->last_fork_time( time );
    $self->scoreboard( '' );
}

my %status = ( A => 'Acccept', B => 'Busy', I => 'Idle' );
sub run {
    my $self  = shift;
    my $proxy = $self->proxy();
    my $kids  = $self->kids();

    ## first phase: update scoreboard
    if ( $self->select()->can_read(1) ) {
        $self->status_read()->sysread( my $buf, 50 ) > 0    # read first 10 changes
          or die "bad read"; # FIXME
        while ( length $buf ) {
            my ( $pid, $status ) = unpack "NA", substr( $buf, 0, 5, "" );
            $proxy->log( HTTP::Proxy::ENGINE, 'ENGINE',
                "Child process $pid updated to $status ($status{$status})" );
            $kids->{$pid} = $status;
        }
        $self->last_active_time(time);
    }

    {
        my $new = join "", values %$kids;
        if ( $new ne $self->scoreboard() ) {
            $proxy->log( HTTP::Proxy::ENGINE, 'ENGINE', "ScoreBoard = $new" );
            $self->scoreboard($new);
        }
    }

    ## second phase: delete dead kids
    while ( ( my $kid = waitpid( -1, WNOHANG ) ) > 0 ) {
        $proxy->{conn}++;    # Cannot use the interface for RO attributes
        $proxy->log( HTTP::Proxy::PROCESS, 'PROCESS',
            "Reaped child process $kid" );
        $proxy->log( HTTP::Proxy::PROCESS, 'PROCESS',
            "Remaining kids: @{[keys %$kids]}" );
        delete $kids->{$kid};
    }

    ## third phase: verify live kids
    if ( time > $self->verify_live_kids_time() + $self->verify_delay() ) {
        for my $kid ( keys %$kids ) {
            next if kill 0, $kid;

            # shouldn't happen normally
            $proxy->log( HTTP::Proxy::ERROR, "ENGINE",
                "Child process $kid found missing" );
            delete $kids->{$kid};
        }
        $self->verify_live_kids_time(time);
    }

    ## fourth phase: launch kids
    my @idlers = grep $kids->{$_} eq "I", keys %$kids;
    if (
        (
            @idlers < $self->min_spare_servers()       # not enough idlers
            or keys %$kids < $self->start_servers()    # not enough overall
        )
        and keys %$kids < $self->max_clients()         # not too many please
        and time > $self->last_fork_time()             # not too fast please
      )
    {
        my $child = fork();
        if ( !defined $child ) {
            $proxy->log( HTTP::Proxy::ERROR, "PROCESS", "Cannot fork" );
        }
        else {
            if ($child) {
                $proxy->log( HTTP::Proxy::PROCESS, "PROCESS",
                    "Forked child process $child" );
                $kids->{$child} = "I";
                $self->last_fork_time(time);
            }
            else {    # child process
                $self->_run_child();
                exit;    # we're done
            }
        }
    }
    elsif (
        (
            @idlers > $self->max_spare_servers()    # too many idlers
            or @idlers > $self->min_spare_servers() # too many lazy idlers
            and time > $self->last_active_time + $self->verify_delay()
        )
        and keys %$kids > $self->start_servers()    # not too few please
      )
    {
        my $victim = $idlers[ rand @idlers ];
        $proxy->log( HTTP::Proxy::ENGINE, "ENGINE",
            "Killing idle child process $victim" );
        kill INT => $victim;                        # pick one at random
        $self->last_active_time(time);
    }

}

sub stop {
    my $self  = shift;
    my $kids  = $self->kids();
    my $proxy = $self->proxy();

    kill 'INT' => keys %$kids;

    # wait for remaining children
    while (%$kids) {
        my $pid = waitpid( -1, WNOHANG );
        last if $pid == 0 || $pid == -1;    # AS/Win32 returns negative PIDs

        $proxy->{conn}++;  # Cannot use the interface for RO attributes
        delete $kids->{$pid};
        $proxy->log( HTTP::Proxy::PROCESS, "PROCESS",
            "Reaped child process $pid" );
        $proxy->log( HTTP::Proxy::PROCESS, "PROCESS",
            "Remaining kids: @$kids" );
    }
}

sub _run_child {
    my $self = shift;

    my $daemon       = $self->proxy()->daemon();
    my $status_write = $self->status_write();

    my $config = IO::Handle->new;
    open $config, __FILE__ or die "Cannot open lock file: $!";

    $SIG{HUP} = $SIG{INT} = $SIG{TERM} = 'DEFAULT';

    my $did = 0;    # processed count

    while ( ++$did <= $self->max_requests_per_child() ) {
        flock $config, LOCK_EX or die "Cannot get flock: $!";

        5 == syswrite $status_write, pack "NA", $$, "A"    # go accept
          or warn "status A: short write";
        my $slave = $daemon->accept() or die "accept: $!";
        flock $config, LOCK_UN or die "Cannot unflock: $!";

        5 == syswrite $status_write, pack "NA", $$, "B"    # go busy
          or warn "status B: short write";
        $slave->autoflush(1);
        
        $SIG{INT} = 'DEFAULT';
        $self->proxy()->serve_connections($slave);

        close $slave;
        5 == syswrite $status_write, pack "NA", $$, "I"    # go idle
          or warn "status I: short write";
    }
}

1;

__END__

=head1 NAME

HTTP::Proxy::Engine::ScoreBoard - A scoreboard-based HTTP::Proxy engine

=head1 SYNOPSIS

    my $proxy = HTTP::Proxy->new( engine => ScoreBoard );

=head1 DESCRIPTION

This module provides a scoreboard-based engine to HTTP::Proxy.

=head1 METHODS

The module defines the following methods, used by HTTP::Proxy main loop:

=over 

=item start()

Initialise the engine.

=item run()

Implements the forking logic: a new process is forked for each new
incoming TCP connection.

=item stop()

Reap remaining child processes.

=back

=head1 SEE ALSO

L<HTTP::Proxy>, L<HTTP::Proxy::Engine>.

=head1 AUTHOR

Philippe "BooK" Bruhat, C<< <book@cpan.org> >>.

Many thanks to Randal L. Schwartz for his help in implementing this module.

=head1 COPYRIGHT

Copyright 2005, Philippe Bruhat.

=head1 LICENSE

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

