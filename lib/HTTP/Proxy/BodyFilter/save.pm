package HTTP::Proxy::BodyFilter::save;

use strict;
use HTTP::Proxy;
use base qw( HTTP::Proxy::BodyFilter );
use Fcntl;
use File::Spec;
use File::Path;
use Carp;

=head1 NAME

HTTP::Proxy::BodyFilter::save - A filter that saves transfered data to a file

=head1 SYNOPSIS

    use HTTP::Proxy;
    use HTTP::Proxy::BodyFilter::save;

    my $proxy = HTTP::Proxy->new;

    # save RFC files as we browse them
    $proxy->push_filter(
        path => qr!/rfc\d+.txt!,
        mime => 'text/plain',
        response => HTTP::Proxy::BodyFilter::save->new(
            template => '%f',
            prefix   => 'rfc',
            keep_old => 1,
        );
    );

    $proxy->start;

=head1 DESCRIPTION

The HTTP::Proxy::BodyFilter::save filter can save HTTP messages (responses
or request) bodies to files. The name of the file is determined by a
template and the URI of the request.

Simply insert this filter in a filter stack, and it will save the data
as it flows through the proxy. Depending on where the filter is located
in the stack, the saved data can be more or less modified.

This filter I<will> create directories if it needs to!

=cut

sub init {
    my $self = shift;

    # options 
    my %args = (
         template   => File::Spec->catfile( '%h', '%P' ),
         no_host    => 0,
         no_dirs    => 0,
         cut_dirs   => 0,
         prefix     => '',
         multiple   => 1,
         keep_old   => 1, # no_clobber in wget parlance
         timestamp  => 0,
         @_
    );
    # keep_old and timestamp can't be selected together
    croak "Can't timestamp and keep older files at the same time"
      if $args{keep_old} && $args{timestamp};

    $self->{"_hpbf_save_$_"} = $args{$_}
      for qw( template no_host no_dirs cut_dirs prefix timestamp
              keep_old multiple );
}

=head2 Constructor

The constructor accepts the following options:

=over 4

=item B<template> I<string>

The file name is build from the C<template> option. The following
placeholders are available:

    %%   a percent sign
    %h   the host
    %p   the path (no leading separator)
    %d   the path (filename removed)
    %f   the filename (or 'index.html' if absent)
    %q   the query string
    %P   the path and the query string,
         separated by '?' (if the query string is not empty)

C</> in the URI path are replaced by the separator used by File::Spec.

The result of the template is modified by the B<no_host>, B<no_dirs>
and B<cut_dirs>.

The default template is the local equivalent of the C<%h/%P> Unix path.

=item B<no_host> I<boolean>

The C<no_host> option makes C<%h> empty. Default is I<false>.

=item B<no_dirs> I<boolean>

The C<no_dirs> option removes all directories from C<%p>, C<%P> and C<%d>.
Default is I<false>.

=item B<cut_dirs> I<number>

The C<cut_dirs> options removes the first I<n> directories from the
content of C<%p>, C<%P> and C<%d>. Default is C<0>.

=item B<prefix> I<string>

The B<prefix> option prepends the given prefix to the filename
created from the template. Default is C<"">.

=item B<multiple> I<boolean>

With the B<multiple> option, saving the same file in the same directory
will result in the original copy of file being preserved and the second
copy being named file.1. If that a file is saved yet again with the same
name, the third copy will be named file.2, and so on.

Default is I<true>.

If B<multiple> is set to I<false> then a file will be overwritten
by the next one with the same name.

=item B<timestamp> I<boolean>

With the C<timestamp> option, the decision as to whether or not to save
a newer copy of a file depends on the local and remote timestamp and
size of the file.

The file is saved only if the date given in the C<Last-Modified> is more
recent than the local file's timestamp.

Default is I<false>.

=item B<keep_old> I<boolean>

The C<keep_old> option will prevent the file to be saved if a file
with the same name already exists. Default is I<false>.

No matter if B<multiple> is set or not, the file will I<not> be saved
if B<keep_old> is set to true.

Here, keep_old is as badly as in wget, 

=back

=cut

sub start {
    my ( $self, $message ) = @_;

    my $uri = $message->isa( 'HTTP::Request' )
            ? $message->uri : $message->request->uri;

    # set the template variables from the URI
    my @segs = $uri->path_segments; # starts with an empty string
    shift @segs;
    splice(@segs, 1, $self->{_hpbf_save_cut_dirs} >= @segs
                     ? @segs - 1 : $self->{_hpbf_save_cut_dirs} );
    my %vars = (
         '%' => '%',
         h   => $self->{_hpbf_save_no_host} ? '' : $uri->host,
         f   => $segs[-1] || 'index.html', # same default as wget
         p   => $self->{_hpbf_save_no_dirs} ? $segs[-1] || 'index.html'
                                            : File::Spec->catfile(@segs),
         q   => $uri->query,
    );
    pop @segs;
    $vars{d} = $self->{_hpbf_save_no_dirs} ? '' : File::Spec->catfile(@segs);
    $vars{P} = $vars{p} . ( $vars{q} ? "?$vars{q}" : '' );

    # create the filename
    my $file = File::Spec->catfile( $self->{_hpbf_save_prefix} || (),
                                    $self->{_hpbf_save_template} );
    $file =~ s/%(.)/$vars{$1}/g;
    $file = File::Spec->rel2abs( $file );

    # internal data initialisation
    $self->{_hpbf_save_filename} = "";
    $self->{_hpbf_save_fh} = undef;

    # create the directory
    my $dir = File::Spec->catdir( (File::Spec->splitpath($file))[ 0, 1 ] );
    eval { mkpath( $dir ) };
    if ($@) {
        $self->proxy->log( HTTP::Proxy::ERROR, "($$) HTBF::save",
                          "Unable to create directory $dir" );
        return;
    }

    # open and lock the file
    my ( $ext, $n, $i ) = ( "", 0 );
    while( ! sysopen( $self->{_hpbf_save_fh}, "$file$ext",
                      O_WRONLY | O_EXCL | O_CREAT ) ) {
        $self->proxy->log( HTTP::Proxy::ERROR, "($$) HPBF::save",
                           "Too many errors opening $file$ext" ), return
          if $i++ - $n == 10; # should be ok now
        if( $self->{_hpbf_save_multiple} ) {
            $ext = "." . ++$n while -e $file.$ext;
            next;
        }
        if( $self->{_hpbf_save_timestamp} ) {
            # FIXME timestamp
        } elsif( $self->{_hpbf_save_keep_old} ) {
            $self->proxy->log( HTTP::Proxy::FILTERS, "($$) HPBF::save",
                               "Skip saving $uri" );
            delete $self->{_hpbf_save_fh}; # it's a closed filehandle
            return;
        } else {
            unlink $file; # FIXME error ?
        }
    }

    # we have an open filehandle
    $self->{_hpbf_save_filename} = $file.$ext;
    binmode( $self->{_hpbf_save_fh} );    # for Win32 and friends
    $self->proxy->log( HTTP::Proxy::FILTERS, "($$) HPBF::save",
                       "Saving $uri to $file$ext" );
}

sub filter {
    my ( $self, $dataref ) = @_;
    return unless exists $self->{_hpbf_save_fh};

    # save the data to the file
    my $res = $self->{_hpbf_save_fh}->syswrite( $$dataref );
    $self->proxy->log( HTTP::Proxy::ERROR, "($$) ERROR: HPBF::save", "$!")
      if ! defined $res;  # FIXME error handling
}

sub end {
    my ($self) = @_;

    # close file
    if( $self->{_hpbf_save_fh} ) {
        $self->{_hpbf_save_fh}->close; # FIXME error handling
    }
}

=head2 Examples

Given a request for the http://search.cpan.org/dist/HTTP-Proxy/ URI,
the filename is computed as follows, depending on the constructor
options:

    No options          -> search.cpan.org/dist/HTTP-Proxy/index.html

    no_host  => 1       -> dist/HTTP-Proxy/index.html

    no_dirs  => 1       -> search.cpan.org/index.html

    no_host  => 1,
    no_dirs  => 1,
    prefix   => 'data'  -> data/index.html

    cut_dirs => 1       -> search.cpan.org/HTTP-Proxy/index.html

    cut_dirs => 2       -> search.cpan.org/index.html

=head1 AUTHOR

Philippe "BooK" Bruhat, E<lt>book@cpan.orgE<gt>.

=head1 THANKS

Thanks to Mat Proud for asking how to store all pages which go through
the proxy to disk, without any processing. The further discussion we
had led to the writing of this class.

Wget(1) provided the inspiration for many of the file naming options.

Thanks to Nicolas Chuche for telling me about C<O_EXCL>.
Thanks to Rafaël Garcia-Suarez and David Rigaudiere for their help on
irc while coding the nasty start() method. C<;-)>

=head1 COPYRIGHT

Copyright 2004, Philippe Bruhat

=head1 LICENSE

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

1;

