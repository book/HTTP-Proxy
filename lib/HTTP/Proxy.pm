package HTTP::Proxy;

use HTTP::Daemon;
use LWP::UserAgent;
use LWP::ConnCache;
use Fcntl ':flock';         # import LOCK_* constants
use POSIX ":sys_wait_h";    # WNOHANG
use IO::Select;
use Carp;

use strict;
use vars qw( $VERSION $AUTOLOAD
  @ISA  @EXPORT @EXPORT_OK %EXPORT_TAGS );

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = ();               # no export by default
@EXPORT_OK = qw( NONE ERROR STATUS PROCESS CONNECT HEADERS FILTER ALL );
%EXPORT_TAGS = ( log => [@EXPORT_OK] );    # only one tag

$VERSION = '0.10';

my $CRLF = "\015\012";                     # "\r\n" is not portable

# standard filters
require HTTP::Proxy::HeaderFilter::standard;    # needs $VERSION

# constants used for logging
use constant ERROR   => -1;
use constant NONE    => 0;
use constant STATUS  => 1;
use constant PROCESS => 2;
use constant CONNECT => 4;
use constant HEADERS => 8;
use constant FILTER  => 16;
use constant ALL     => 31;

# Methods we can forward
my @METHODS = qw( OPTIONS GET HEAD POST PUT DELETE TRACE );

# useful regexes (from RFC 2616 BNF grammar)
my %RX;
$RX{token}  = qr/[-!#\$%&'*+.0-9A-Z^_`a-z|~]+/;
$RX{mime}   = qr($RX{token}/$RX{token});
$RX{method} = '(?:' . join ( '|', @METHODS ) . ')';
$RX{method} = qr/$RX{method}/;

=pod

=head1 NAME

HTTP::Proxy - A pure Perl HTTP proxy

=head1 SYNOPSIS

    use HTTP::Proxy;

    # initialisation
    my $proxy = HTTP::Proxy->new( port => 3128 );

    # alternate initialisation
    my $proxy = HTTP::Proxy->new;
    $proxy->port( 3128 ); # the classical accessors are here!

    # you can also use your own UserAgent
    my $agent = LWP::RobotUA->new;
    $proxy->agent( $agent );

    # this is a MainLoop-like method
    $proxy->start;

=head1 DESCRIPTION

This module implements a HTTP proxy, using a HTTP::Daemon to accept
client connections, and a LWP::UserAgent to ask for the requested pages.

The most interesting feature of this proxy object is its hability to
filter the HTTP requests and responses through user-defined filters.

=head1 METHODS

=head2 Constructor

=cut

sub new {
    my $class = shift;

    # some defaults
    my $self = {
        agent    => undef,
        chunk    => 4096,
        control  => 'proxy',
        daemon   => undef,
        host     => 'localhost',
        logfh    => *STDERR,
        logmask  => NONE,
        maxchild => 10,
        maxconn  => 0,
        maxserve => 10,
        port     => 8080,
        timeout  => 60,
        @_,
    };

    # non modifiable defaults
    %$self = ( %$self, conn => 0, loop => 1 );
    bless $self, $class;

    # ugly way to set control_regex
    $self->control( $self->control );

    return $self;
}

=head2 Accessors

The HTTP::Proxy has several accessors.

Called with arguments, the accessor returns the current value.
Called with a single argument, it set the current value and
returns the previous one, in case you want to keep it.

If you call a read-only accessor with a parameter, this parameter
will be ignored.

The defined accessors are (in alphabetical order):

=over 4

=item agent

The LWP::UserAgent object used internally to connect to remote sites.

=item conn (read-only)

The number of connections processed by this HTTP::Proxy instance.

=item control

The default hostname for controlling the proxy (see L<CONTROL>).
The default is "C<proxy>", which corresponds to the URL
http://proxy/, where port is the listening port of the proxy).

=cut

sub control {
    my $self = shift;
    my $old  = $self->{control};
    if (@_) {
        my $control = shift;
        $self->{control}       = $control;
        $self->{control_regex} = qr!^http://$control(?:/(\w+))?!;
    }
    return $old;
}

# control_regex is private

=item daemon

The HTTP::Daemon object used to accept incoming connections.
(You usually never need this.)

=item host

The proxy HTTP::Daemon host (default: 'localhost').

=item logfh

A filehandle to a logfile (default: *STDERR).

=item logmask( [$mask] )

Be verbose in the logs (default: NONE).

Here are the various elements that can be added to the mask:
 NONE    - Log only errors
 STATUS  - Requested URL, reponse status and total number
           of connections processed
 PROCESS - Subprocesses information (fork, wait, etc.)
 HEADERS - Full request and response headers are sent along
 FILTER  - Filter information
 ALL     - Log all of the above

If you only want status and process information, you can use:

    $proxy->logmask( STATUS | PROCESS );

Note that all the logging constants are not exported by default, but 
by the C<:log> tag. They can also be exported one by one.

=item maxchild

The maximum number of child process the HTTP::Proxy object will spawn
to handle client requests (default: 16).

=item maxconn

The maximum number of TCP connections the proxy will accept before
returning from start(). 0 (the default) means never stop accepting
connections.

=item maxserve

The maximum number of requests the proxy will serve in a single connection.
(same as MaxRequestsPerChild in Apache)

=item port

The proxy HTTP::Daemon port (default: 8080).

=item timeout

The timeout used by the internal LWP::UserAgent (default: 60).

=cut

sub timeout {
    my $self = shift;
    my $old  = $self->{timeout};
    if (@_) {
        $self->{timeout} = shift;
        $self->agent->timeout( $self->{timeout} ) if $self->agent;
    }
    return $old;
}

=item url (read-only)

The url where the proxy can be reached.

=cut

sub url {
    my $self = shift;
    if ( not defined $self->daemon ) {
        carp "HTTP daemon not started yet";
        return undef;
    }
    return $self->daemon->url;
}

=back

=cut

# normal accessors
for my $attr (
    qw( agent chunk daemon host logfh maxchild maxconn maxserve port
    request response logmask )
  )
{
    no strict 'refs';
    *{"HTTP::Proxy::$attr"} = sub {
        my $self = shift;
        my $old  = $self->{$attr};
        $self->{$attr} = shift if @_;
        return $old;
      }
}

# read-only accessors
for my $attr (qw( conn control_regex loop )) {
    no strict 'refs';
    *{"HTTP::Proxy::$attr"} = sub { return $_[0]->{$attr} }
}

=head2 The start() method

This method works like Tk's C<MainLoop>: you hand over control to the
HTTP::Proxy object you created and configured.

If C<maxconn> is not zero, start() will return after accepting
at most that many connections.

=cut

sub start {
    my $self = shift;
    my @kids;

    # some initialisation
    $self->init;
    $SIG{INT} = $SIG{KILL} = sub { $self->{loop} = 0 };

    # the main loop
    my $select = IO::Select->new( $self->daemon );
    while ( $self->loop ) {

        # check for new connections
        my @ready = $select->can_read(0.01);
        for my $fh (@ready) {    # there's only one, anyway
            if ( @kids >= $self->maxchild ) {
                $self->log( PROCESS, "Too many child process" );
                select( undef, undef, undef, 1 );
                last;
            }

            # accept the new connection
            my $conn  = $fh->accept;
            my $child = fork;
            if ( !defined $child ) {
                $conn->close;
                $self->log( ERROR, "Cannot fork" );
                $self->maxchild( $self->maxchild - 1 )
                  if $self->maxchild > @kids;
                $self->log( ERROR, "Really cannot fork, abandon" ), last
                  if $self->maxchild == 0;
                next;
            }

            # the parent process
            if ($child) {
                $self->log( PROCESS, "Forked child process $child" );
                push @kids, $child;
            }

            # the child process handles the whole connection
            else {
                $SIG{INT} = 'DEFAULT';
                $self->serve_connections($conn);
                exit;    # let's die!
            }
        }

        # handle zombies
        $self->_reap( \@kids ) if @kids;

        # this was the last child we forked
        last if $self->maxconn && $self->conn >= $self->maxconn;
    }

    # wait for remaining children
    kill INT => @kids;
    $self->_reap( \@kids ) while @kids;

    $self->log( STATUS, "Processed " . $self->conn . " connection(s)" );
    return $self->conn;
}

# private reaper sub
sub _reap {
    my ( $self, $kids ) = @_;
    while (1) {
        my $pid = waitpid( -1, &WNOHANG );
        last if $pid == 0 || $pid == -1;    # AS/Win32 returns negative PIDs
        @$kids = grep { $_ != $pid } @$kids;
        $self->{conn}++;    # Cannot use the interface for RO attributes
        $self->log( PROCESS, "Reaped child process $pid" );
        $self->log( PROCESS, "Remaining kids: @$kids" );
    }
}

# semi-private init method
sub init {
    my $self = shift;

    # must be run only once
    return if $self->{_init}++;

    $self->_init_daemon if ( !defined $self->daemon );
    $self->_init_agent  if ( !defined $self->agent );

    # specific agent config
    $self->agent->requests_redirectable( [] );
    $self->agent->agent('');    # for TRACE support
    $self->agent->protocols_allowed( [qw( http https ftp gopher )] );

    # standard header filters
    $self->{headers}{request}  = HTTP::Proxy::FilterStack->new;
    $self->{headers}{response} = HTTP::Proxy::FilterStack->new;

    # the same standard filter is used to handle headers
    my $std = HTTP::Proxy::HeaderFilter::standard->new();
    $self->{headers}{request}->push(  [ sub { 1 }, $std ] );
    $self->{headers}{response}->push( [ sub { 1 }, $std ] );

    # standard body filters
    $self->{body}{request}  = HTTP::Proxy::FilterStack->new(1);
    $self->{body}{response} = HTTP::Proxy::FilterStack->new(1);

    return;
}

#
# private init methods
#

sub _init_daemon {
    my $self = shift;
    my %args = (
        LocalPort => $self->port,
        ReuseAddr => 1,
    );
    delete $args{LocalPort} unless $self->port;    # 0 means autoselect
    my $daemon = HTTP::Daemon->new(%args)
      or die "Cannot initialize proxy daemon: $!";
    $self->daemon($daemon);

    return $daemon;
}

sub _init_agent {
    my $self  = shift;
    my $agent = LWP::UserAgent->new(
        env_proxy  => 1,
        keep_alive => 2,
        parse_head => 0,
        timeout    => $self->timeout,
      )
      or die "Cannot initialize proxy agent: $!";
    $self->agent($agent);
    return $agent;
}

# This is the internal "loop" that lets the child process process the
# incoming connections.

sub serve_connections {
    my ( $self, $conn ) = @_;
    my $response;

    my ( $last, $served ) = ( 0, 0 );
    while ( my $req = $conn->get_request() ) {

        $served++;

        # Got a request?
        unless ( defined $req ) {
            $self->log( ERROR, "($$) Getting request failed:", $conn->reason );
            return;
        }
        $self->log( STATUS, "($$) Request:", $req->method . ' ' . $req->uri );

        # can we forward this method?
        if ( !grep { $_ eq $req->method } @METHODS ) {
            $response = new HTTP::Response( 501, 'Not Implemented' );
            $response->content(
                "Method " . $req->method . " is not supported by this proxy." );
            goto SEND;
        }

        # can we serve this protocol?
        if ( !$self->agent->is_protocol_supported( my $s = $req->uri->scheme ) )
        {
            $response = new HTTP::Response( 501, 'Not Implemented' );
            $response->content("Scheme $s is not supported by this proxy.");
            goto SEND;
        }

        # massage the request
        $self->request($req);
        $self->{headers}{request}->filter( $req->headers, $req );

        # FIXME I don't know how to get the LWP::Protocol objet...
        $self->{body}{request}->filter( $req->content_ref, $req, undef );
        $self->log( HEADERS, "($$) Request:", $req->headers->as_string );

        # pop a response
        my ( $sent, $chunked ) = ( 0, 0 );
        $response = $self->agent->simple_request(
            $req,
            sub {
                my ( $data, $response, $proto ) = @_;

                # first time, filter the headers
                if ( !$sent ) {
                    $self->response($response);
                    $self->{headers}{response}
                      ->filter( $response->headers, $response );
                    $response->remove_header("Content-Length");

                    # this is adapted from HTTP::Daemon
                    if ( $conn->antique_client ) { $last++ }
                    else {
                        my $code = $response->code;
                        $conn->send_status_line( $code, $response->message,
                            $response->protocol );
                        if ( $code =~ /^(1\d\d|[23]04)$/ ) {

                            # make sure content is empty
                            $response->remove_header("Content-Length");
                            $response->content('');
                        }
                        elsif ($response->request
                            && $response->request->method eq "HEAD" )
                        {    # probably OK, says HTTP::Daemon
                        }
                        else {
                            if ( $conn->proto_ge("HTTP/1.1") ) {
                                $response->push_header(
                                    "Transfer-Encoding" => "chunked" );
                                $chunked++;
                                $response->push_header(
                                    "Connection" => "close" )
                                    if $served >= $self->maxserve;
                            }
                            else {
                                $last++;
                                $conn->force_last_request;
                            }
                        }
                        print $conn $response->headers_as_string($CRLF);
                        print $conn $CRLF;    # separates headers and content
                    }
                    $sent++;
                }

                # filter and send the data
                $self->log( FILTER, "($$) Filter:",
                    "got " . length($data) . " bytes of body data" );
                $self->{body}{response}->filter( \$data, $response, $proto );
                if ($chunked) {
                    printf $conn "%x%s%s%s", length($data), $CRLF, $data, $CRLF
                      if length($data);    # the filter may leave nothing
                }
                else {
                    print $conn $data;
                }
            },
            $self->chunk
        );

        # remove the header added by LWP::UA before it sends the response back
        $response->remove_header('Client-Date');

        # do a last pass, in case there was something left in the buffers
        my $data = "";    # FIXME $protocol is undef here too
        $self->{body}{response}->filter_last( \$data, $response, undef );
        if ( length $data ) {
            if ($chunked) {
                printf $conn "%x%s%s%s", length($data), $CRLF, $data, $CRLF;
            }
            else {
                print $conn $data;
            }
        }

        # last chunk
        print $conn "0$CRLF$CRLF" if $chunked;    # no trailers either

        # what about X-Died and X-Content-Range?

      SEND:

        # responses that weren't filtered through callbacks
        # FIXME make sure there is no content to filter
        if ( !$sent ) {
            $self->response($response);
            $self->{headers}{response}->filter( $response->headers, $response );
            $conn->send_response($response);
        }

        # FIXME ftp, gopher
        if ( $req->uri->scheme =~ /^(?:ftp|gopher)$/ && $response->is_success )
        {
            $conn->print( $response->content );
        }

        $self->log( STATUS,  "($$) Response:", $response->status_line );
        $self->log( HEADERS, "($$) Response:", $response->headers->as_string );
        last if $last || $served >= $self->maxserve;
    }
    $self->log( CONNECT, "($$) Connection closed by the client" )
      if !$last
      and $served < $self->maxserve;
    $self->log( PROCESS, "($$) Served $served requests" );
    $conn->close;
}

=head2 Filters

You can alter the way the default HTTP::Proxy works by pluging callbacks
at different stages of the request/response handling.

When a request is received by the HTTP::Proxy object, it is filtered through
a standard filter that transform this request accordingly to RFC 2616
(by adding the Via: header, and a few other transformations).

The response is also filtered in the same manner. There is a total of four
filter chains: C<request-headers>, C<request-body>, C<reponse-headers> and
C<response-body>.

You can add your own filters to the default ones with the
push_filter() method. The method push a filter on the appropriate
filter stack.

    $proxy->push_filter( response => $filter );

The headers/body category is determined by the type of the filter.
There are two base classes for filters, which are
HTTP::Proxy::HeaderFilter and HTTP::Proxy::BodyFilter (the names
are self-explanatory). See the documentation of those two classes
to find out how to write your own header or body filters.

The named parameter is used to determine the request/response part.

It is possible to push the same filter on the request and response
stacks, as in the following example:

    $proxy->push_filter( request => $filter, response => $filter );

If several filters match the message, they will be applied in the order
they were pushed on their filter stack.

Named parameters can be used to create the match routine. They are: 

    mime   - the MIME type (for a response-body filter)
    method - the request method
    scheme - the URI scheme         
    host   - the URI authority (host:port)
    path   - the URI path

The filters are applied only when all the the parameters match the
request or the response. All these named parameters have default values,
which are:

    mime   => 'text/*'
    method => 'GET, POST, HEAD'
    scheme => 'http'
    host   => ''
    path   => ''

The C<mime> parameter is a glob-like string, with a required C</>
character and a C<*> as a joker. Thus, C<*/*> matches I<all> responses,
and C<""> those with no C<Content-Type:> header. To match any
reponse (with or without a C<Content-Type:> header), use C<undef>.

The C<mime> parameter is only meaningful with the C<response-body>
filter stack. It is ignored if passed to any other filter stack.

The C<method> and C<scheme> parameters are strings consisting of
comma-separated values. The C<host> and C<path> parameters are regular
expressions.

A match routine is compiled by the proxy and used to check if a particular
request or response must be filtered through a particular filter.

It is also possible to push several filters on the same stack with
the same match subroutine:

    # convert italics to bold
    $proxy->push_filter(
        mime     => 'text/html',
        response => HTTP::Proxy::BodyFilter::tags->new(),
        response =>
        HTTP::Proxy::BodyFilter::simple->new( sub { s!(</?)i>!$1b>!ig } )
    );

For more details regarding the creation of new filters, check the
HTTP::Proxy::HeaderFilter and HTTP::Proxy::BodyFilter documentation.

Here's an example of subclassing a base filter class:

    # fixes a common typo ;-)
    # but chances are that this will modify a correct URL
    {
        package FilterPerl;
        use base qw( HTTP::Proxy::BodyFilter );

        sub filter {
	    my ( $self, $dataref, $message, $protocol, $buffer ) = @_;
            $$dataref =~ s/PERL/Perl/g;
        }
    }
    $proxy->push_filter( response => FilterPerl->new() );

Other examples can be found in the documentation for
HTTP::Proxy::HeaderFilter, HTTP::Proxy::BodyFilter,
HTTP::Proxy::HeaderFilter::simple, HTTP::Proxy::BodyFilter::simple.

    # a simple anonymiser
    # see eg/anonymiser.pl for the complete code
    $proxy->push_filter(
        mime    => undef,
        request => HTTP::Proxy::HeaderFilter::simple->new(
            sub { $_[0]->remove_header(qw( User-Agent From Referer Cookie )) },
        ),
        response => HTTP::Proxy::HeaderFilter::simple->new(
            sub { $_[0]->revome_header(qw( Set-Cookie )); },
        )
    );

IMPORTANT: If you use your own LWP::UserAgent, you must install it
before your calls to push_filter(), otherwise
the match method will make wrong assumptions about the schemes your
agent supports.

=cut

sub push_filter {
    my $self = shift;
    my %arg  = (
        mime   => 'text/*',
        method => 'GET, POST, HEAD',
        scheme => 'http',
        host   => '',
        path   => '',
    );

    # parse parameters
    for( my $i = 0; $i < @_ ; $i += 2 ) {
        next if $_[$i] !~ /^(mime|method|scheme|host|path)$/;
        $arg{$_[$i]} = $_[$i+1];
        splice @_, $i, 2;
    }
    croak "Odd number of arguments" if @_ % 2;

    # the proxy must be initialised
    $self->init;

    # prepare the variables for the closure
    my ( $mime, $method, $scheme, $host, $path ) =
      @arg{qw( mime method scheme host path )};

    if ( defined $mime && $mime ne '' ) {
        $mime =~ m!/! or croak "Invalid MIME type definition: $mime";
        $mime =~ s/\*/$RX{token}/;    #turn it into a regex
        $mime = qr/^$mime(?:$|\s*;?)/;
    }

    my @method = split /\s*,\s*/, $method;
    for (@method) { croak "Invalid method: $_" if !/$RX{method}/ }
    $method = @method ? '(?:' . join ( '|', @method ) . ')' : '';
    $method = qr/^$method$/;

    my @scheme = split /\s*,\s*/, $scheme;
    for (@scheme) {
        croak "Unsupported scheme: $_"
          if !$self->agent->is_protocol_supported($_);
    }
    $scheme = @scheme ? '(?:' . join ( '|', @scheme ) . ')' : '';
    $scheme = qr/$scheme/;

    $host ||= '.*';
    $path ||= '.*';

    # push the filter and its match method on the correct stack
    while(@_) {
        my ($message, $filter ) = (shift, shift);
        croak "'$message' is not a filter stack"
          unless $message =~ /^(request|response)$/;
        
        croak "Not a Filter reference for filter queue $message"
          unless ref( $filter )
          && ( $filter->isa('HTTP::Proxy::HeaderFilter')
            || $filter->isa('HTTP::Proxy::BodyFilter') );

        my $stack;
        $stack = 'headers' if $filter->isa('HTTP::Proxy::HeaderFilter');
        $stack = 'body'    if $filter->isa('HTTP::Proxy::BodyFilter');

        # MIME can only match on reponse
        my $mime = $mime;
        undef $mime if $message eq 'request';

        # compute the match sub as a closure
        # for $self, $mime, $method, $scheme, $host, $path
        my $match = sub {
            if ( defined $mime ) {
                return 0
                  if $self->{response}->headers->header('Content-Type') !~
                  $mime;
            }
            return 0 if $self->{request}->method !~ $method;
            return 0 if $self->{request}->uri->scheme !~ $scheme;
            return 0 if $self->{request}->uri->authority !~ $host;
            return 0 if $self->{request}->uri->path !~ $path;
            return 1;    # it's a match
        };

        # push it on the corresponding FilterStack
        $self->{$stack}{$message}->push( [ $match, $filter ] );
    }
}

=over 4

=item log( $level, $prefix, $message )

Adds $message at the end of C<logfh>, if $level matches C<logmask>.
The log() method also prints a timestamp.

The output looks like:

    [Thu Dec  5 12:30:12 2002] $prefix $message

If $message is a multiline string, several log lines will be output,
each starting with $prefix.

=cut

sub log {
    my $self  = shift;
    my $level = shift;
    my $fh    = $self->logfh;

    return unless $self->logmask & $level;

    my ( $prefix, $msg ) = ( @_, '' );
    my @lines = split /\n/, $msg;
    @lines = ('') if not @lines;

    flock( $fh, LOCK_EX );
    print $fh "[" . localtime() . "] $prefix $_\n" for @lines;
    flock( $fh, LOCK_UN );
}

=back

=cut

=head1 EXPORTED SYMBOLS

No symbols are exported by default. The C<:log> tag exports all the
logging constants.

=head1 BUGS

This does not work under Windows, but I can't see why, and do not have
a development platform under that system. Patches and explanations
very welcome.

The Date: header is duplicated.

This is still beta software, expect some interfaces to change as
I receive feedback from users.

=head1 AUTHOR

Philippe "BooK" Bruhat, E<lt>book@cpan.orgE<gt>.

The module has its own web page at http://http-proxy.mongueurs.net/
complete with older versions and repository snapshot.

=head1 THANKS

Many people helped me during the development of this module, either on
mailing-lists, irc or over a beer in a pub...

So, in no particular order, thanks to the libwww-perl team for such
a terrific suite of modules, Michael Schwern (tips for testing while
forking), the Paris.pm folks (forking processes, chunked encoding)
and my growing user base... C<;-)>

=head1 COPYRIGHT

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

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
package HTTP::Proxy::FilterStack;

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
sub active { return @{ $_[0]->{current} }; }

#
# the actual filtering is done here
#
sub filter {
    my $self = shift;

    # first time we're called
    if ( not defined $self->{current} ) {

        # select the filters that match
        $self->{current} =
          [ map { $_->[1] } grep { $_->[0]->() } @{ $self->{filters} } ];

        # create the buffers
        if ( $self->{body} ) {
            $self->{buffers} = [ ( "" ) x @{ $self->{current} } ];
            $self->{buffers} = [ \( @{ $self->{buffers} } ) ];
        }

        # start the filter if needed
        for ( @{ $self->{current} } ) { $_->start if $_->can('start'); }
    }

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
    else { $_->filter(@_) for @{ $self->{current} }; }
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

    # clean up the mess for next time
    $self->{buffers} = [];
    $self->{current} = undef;
}

1;
