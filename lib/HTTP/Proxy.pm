package HTTP::Proxy;

use HTTP::Daemon;
use LWP::UserAgent;
use LWP::ConnCache;
use CGI;
use Fcntl ':flock';    # import LOCK_* constants
use POSIX;
use Sys::Hostname;
use Carp;

use strict;
use vars qw( $VERSION $AUTOLOAD );

$VERSION = 0.05;

my $CRLF = "\015\012";    # "\r\n" is not portable

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

This module implements a HTTP Proxy, using a HTTP::Daemon to accept
client connections, and a LWP::UserAgent to ask for the requested pages.

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
        maxchild => 10,
        maxconn  => 0,
        logfh    => *STDERR,
        port     => 8080,
        verbose  => 0,
        @_,
    };

    # non modifiable defaults
    %$self = ( %$self, conn => 0, loop => 1 );
    bless $self, $class;

    # ugly way to set control_regex
    $self->control( $self->control );

    return $self;
}

# AUTOLOADed attributes
my $all_attr = qr/^(?:agent|chunk|conn|control_regex|daemon|host|logfh|
                      loop|maxchild|maxconn|port|request|response|
                      verbose)$/x;

# read-only attributes
my $ro_attr = qr/^(?:conn|control_regex|loop)$/;

=head2 Accessors

The HTTP::Proxy has several accessors. They are all AUTOLOADed.

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

=item maxchild

The maximum number of child process the HTTP::Proxy object will spawn
to handle client requests (default: 16).

=item maxconn

The maximum number of connections the proxy will accept before returning
from start(). 0 (the default) means never stop accepting connections.

=item port

The proxy HTTP::Daemon port (default: 8080).

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

=item verbose

Be verbose in the logs (default: 0).

Here are the various log levels:
 0 - All errors
 1 - Requested URL, reponse status and total number of connections processed
 2 -
 3 - Subprocesses information (fork, wait, etc.)
 4 -
 5 - Full request and response headers are sent along

=back

=cut

sub AUTOLOAD {

    # we don't DESTROY
    return if $AUTOLOAD =~ /::DESTROY/;

    # fetch the attribute name
    $AUTOLOAD =~ /.*::(\w+)/;
    my $attr = $1;

    # must be one of the registered subs
    if ( $attr =~ $all_attr ) {
        no strict 'refs';
        my $rw = 1;
        $rw = 0 if $attr =~ $ro_attr;

        # create and register the method
        *{$AUTOLOAD} = sub {
            my $self = shift;
            my $old  = $self->{$attr};
            $self->{$attr} = shift if @_ && $rw;
            return $old;
        };

        # now do it
        goto &{$AUTOLOAD};
    }
    croak "Undefined method $AUTOLOAD";
}

=head2 The start() method

This method works like Tk's C<MainLoop>: you hand over control to the
HTTP::Proxy object you created and configured.

If C<maxconn> is not zero, start() will return after accepting
at most that many connections.

=cut

sub start {
    my $self = shift;
    $self->init;

    my @kids;
    my $reap;
    my $hupped;

    # zombies reaper
    my $reaper;
    $reaper = sub {
        $reap++;
        $SIG{CHLD} = $reaper;    # for sysV systems
    };
    $SIG{CHLD} = $reaper;
    $SIG{HUP}  = sub { $hupped++ };

    # the main loop
    my $daemon = $self->daemon;
    while ( $self->loop ) {

        # prefork children process
        for ( 1 .. $self->maxchild - @kids ) {

            my $child = fork;
            if ( !defined $child ) {
                $self->log( 0, "Cannot fork" );
                $self->maxchild( $self->maxchild - 1 ) if $self->maxchild > 1;
                next;
            }

            # the parent process
            if ($child) {
                $self->log( 3, "Preforked child process $child" );
                push @kids, $child;
            }

            # the child process handles the whole connection
            else {
                $self->serve_connections($daemon);
                exit;    # let's die!
            }
        }

        # wait for a signal
        POSIX::pause();

        # handle zombies
        while ($reap) {
            my $pid = wait;
            @kids = grep { $_ != $pid } @kids;
            $self->{conn}++;    # Cannot use the interface for RO attributes
            $self->log( 3, "Reaped child process $pid" );
            $reap--;
        }

        # did a child send us information?
        if ($hupped) {

            # TODO
        }

        # this was the last child we forked
        last if $self->maxconn && $self->conn >= $self->maxconn;
    }

    # wait for remaining children
    $self->log( 3, "Remaining kids: @kids" );
    kill INT => @kids;

    while (@kids) {
        my $pid = wait;
        @kids = grep { $_ != $pid } @kids;
        $self->log( 3, "Waited for child process $pid" );
    }

    $self->log( 1, "Processed " . $self->conn . " connection(s)" );
    return $self->conn;
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
    $self->{headers}{request} = [ [ sub { 1 }, \&_proxy_headers_filter ] ];
    $self->{headers}{response} = [
        [ sub { 1 }, \&_proxy_headers_filter ],

        # We do not support keep-alive connections for the moment
        [ sub { 1 }, sub { $_[0]->header( Connection => 'close' ) } ]
    ];

    # standard bodyfilters
    $self->{body}{request}  = [];
    $self->{body}{response} = [];

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
    $daemon->product_tokens("HTTP-Daemon/$VERSION");
    $self->daemon($daemon);
    return $daemon;
}

sub _init_agent {
    my $self  = shift;
    my $agent = LWP::UserAgent->new(
        env_proxy  => 1,
        keep_alive => 2,
      )
      or die "Cannot initialize proxy agent: $!";
    $self->agent($agent);
    return $agent;
}

# This is the internal "loop" that lets the child process process the
# incoming connections.

sub serve_connections {
    my ( $self, $daemon ) = @_;
    my $response;

    my $conn = $daemon->accept;
    $SIG{INT} = 'IGNORE';    # don't interrupt while we talk to a client
    my $req = $conn->get_request();

    # Got a request?
    unless ( defined $req ) {
        $self->log( 0, "($$) Getting request failed:", $conn->reason );
        return;
    }
    $self->log( 1, "($$) Request:", $req->method . ' ' . $req->uri );

    # can we forward this method?
    if ( !grep { $_ eq $req->method } @METHODS ) {
        $response = new HTTP::Response( 501, 'Not Implemented' );
        $response->content(
            "Method " . $req->method . " is not supported by this proxy." );
        goto SEND;
    }

    # can we serve this protocol?
    if ( !$self->agent->is_protocol_supported( my $s = $req->uri->scheme ) ) {
        $response = new HTTP::Response( 501, 'Not Implemented' );
        $response->content("Scheme $s is not supported by this proxy.");
        goto SEND;
    }

    # massage the request
    $self->request($req);
    $self->filter_headers('request');
    $self->filter_body('request');
    $self->log( 5, "($$) Request:", $req->headers->as_string );

    # pop a response
    my ( $sent, $buf ) = ( 0, '' );
    $response = $self->agent->simple_request(
        $req,
        sub {
            my ( $data, $response, $proto ) = @_;

            # first time, filter the headers
            if ( !$sent ) {
                $self->response($response);
                $self->filter_headers('response');
                $self->log( 1, "($$) Response:", $response->status_line );
                $self->log( 5, "($$) Response:",
                    $response->headers->as_string );

                # send the headers
                $conn->print( $HTTP::Daemon::PROTO, ' ', $response->status_line,
                    $CRLF, $response->headers->as_string($CRLF), $CRLF );
                $sent++;
            }

            # filter and send the data
            $self->log( 6, "($$) Filter:",
                "got " . length($data) . " bytes of body data" );
            $self->filter_body( 'response', \$data, $proto );
            $conn->print($data);
        },
        $self->chunk
    );

    # only success (2xx) responses are filtered
    if ( !$response->is_success ) {
        $self->response($response);
        $self->filter_headers('response');
        $self->log( 1, "($$) Response:", $response->status_line );
        $self->log( 5, "($$) Response:", $response->headers->as_string );
    }

    # what about X-Died and X-Content-Range?

    $SIG{INT} = 'DEFAULT', return if $sent;

  SEND:

    # send the response
    if ( $req->uri->scheme =~ /^(?:ftp|gopher)$/ && $response->is_success ) {
        $conn->print( $response->content );
    }
    else {
        $conn->print( $HTTP::Daemon::PROTO, ' ', $response->status_line, $CRLF,
            $response->headers->as_string($CRLF), $CRLF );
        if ( !$response->content && $response->is_error ) {
            $response->content( $response->error_as_HTML );
        }
        $conn->print( $response->content );
    }
    $self->log( 1, "($$) Response:", $response->status_line );
    $self->log( 5, "($$) Response:", $response->headers->as_string );
    $SIG{INT} = 'DEFAULT';
}

=head2 Callbacks

You can alter the way the default HTTP::Proxy works by pluging callbacks
at different stages of the request/response handling.

When a request is received by the HTTP::Proxy object, it is filtered through
a standard filter that transform this request accordingly to RFC 2616
(by adding the Via: header, and a few other transformations).

The response is also filtered in the same manner. There is a total of four
filter chains: C<request-headers>, C<request-body>, C<reponse-headers> and
C<response-body>.

You can add your own filters to the default ones with the
push_header_filter() and the push_body_filter() methods. Both methods
work more or less the same way: they push a header filter on the
corresponding filter stack.

    $proxy->push_body_filter( response => $coderef );

The name of the method called gives the headers/body part while the
named parameter give the request/response part.

It is possible to push the same coderef on the request and response
stacks, as in the following example:

    $proxy->push_header_filter( request => $coderef, response => $coderef );
 
Named parameters can be added. They are:

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

The signature for the "headers" filters is:

    sub header_filter { my ( $headers, $message) = @_; ... }

where $header is a HTTP::Headers object, and $message is either a
HTTP::Request or a HTTP::Response object.

The signature for the "body" filters is:

    sub body_filter { my ( $dataref, $message, $protocol ) = @_; ... }

$dataref is a reference to the chunk of data received.

Note that this subroutine signature looks a lot like that of the callbacks
of LWP::UserAgent (except that $message is either a HTTP::Request or a
HTTP::Response object).

Here are a few example filters:

    # fixes a common typo ;-)
    # but chances are that this will modify a correct URL
    $proxy->push_body_filter( response => sub { $$_[0] =~ s/PERL/Perl/g } );

    # mess up trace requests
    $proxy->push_headers_filter(
        method   => 'TRACE',
        response => sub {
            my $headers = shift;
            $headers->header( X_Trace => "Something's wrong!" );
        },
    );

    # a simple anonymiser
    $proxy->push_headers_filter(
        mime    => undef,
        request => sub {
            $_[0]->remove_header(qw( User-Agent From Referer Cookie ));
        },
        response => sub {
            $_[0]->revome_header(qw( Set-Cookie )),;
        },
    );

IMPORTANT: If you use your own LWP::UserAgent, you must install it
before your calls to push_headers_filter() or push_body_filter(), or
the match method will make wrong assumptions about the schemes your
agent supports.

=over 4

=cut

# internal method
# please use push_headers_filters() and push_body_filter()

sub _push_filter {
    my $self = shift;
    my %arg  = (
        mime   => 'text/*',
        method => 'GET, POST, HEAD',
        scheme => 'http',
        host   => '',
        path   => '',
        @_
    );

    # argument checking
    croak "No filter type defined" if ( !exists $arg{part} );
    croak "Bad filter queue: $arg{part}"
      if ( $arg{part} !~ /^(?:headers|body)$/ );
    if ( !exists $arg{request} && !exists $arg{response} ) {
        croak "No message type defined for filter";
    }

    # the proxy must be initialised
    $self->init;

    # prepare the variables for the closure
    my ( $mime, $method, $scheme, $host, $path ) =
      @arg{qw( mime method scheme host path )};

    if ( defined $mime && $mime ne '' ) {
        $mime =~ m!/! or croak "Invalid MIME type definition: $mime";
        $mime =~ s/\*/$RX{token}/;    #turn it into a regex
        $mime = qr/^$mime/;
    }

    my @method = split /\s*,\s*/, $method;
    for (@method) { croak "Invalid method: $_" if !/$RX{method}/ }
    $method = @method ? '' : '(?:' . join ( '|', @method ) . ')';
    $method = qr/$method/;

    my @scheme = split /\s*,\s*/, $scheme;
    for (@scheme) {
        croak "Unsupported scheme" if !$self->agent->is_protocol_supported($_);
    }
    $scheme = @scheme ? '' : '(?:' . join ( '|', @scheme ) . ')';
    $scheme = qr/$scheme/;

    # push the filter and its match method on the correct stack
    for my $message ( grep { exists $arg{$_} } qw( request response ) ) {
        croak "Not a CODE reference for filter queue $message"
          if ref $arg{$message} ne 'CODE';

        # MIME can only match on reponse
        my $mime = $mime;
        undef $mime if $message eq 'request';

        # compute the match sub as a closure
        # for $self, $mime, $method, $scheme, $host, $path
        my $match = sub {
            return 0
              if ( defined $mime
                && $self->{response}->headers->header('Content-Type') !~
                $mime );
            return 0 if $self->{request}->method !~ $method;
            return 0 if $self->{request}->uri->scheme !~ $scheme;
            return 0 if $self->{request}->uri->authority !~ $host;
            return 0 if $self->{request}->uri->path !~ $path;
            return 1;    # it's a match
        };
        push @{ $self->{ $arg{part} }{$message} }, [ $match, $arg{$message} ];
    }
}

=item push_headers_filter( type => coderef, %args )

=cut

sub push_headers_filter { _push_filter( @_, part => 'headers' ); }

=item push_body_filter( type => coderef, %args )

=cut

sub push_body_filter { _push_filter( @_, part => 'body' ); }

# the very simple filter_* methods

# filter_headers( $type )
#
# type is either 'request' or 'response'

sub filter_headers {
    my ( $self, $type ) = ( shift, shift );

    # argument checking
    croak "Bad filter type: $type" if $type !~ /^re(?:quest|sponse)$/;

    my $message = $self->{$type};
    my $headers = $message->headers;

    # filter the headers
    for ( @{ $self->{headers}{$type} } ) {
        $_->[1]->( $headers, $message ) if $_->[0]->();
    }
}

# filter_body( $type, $dataref, $proto )
#
# type is either 'request' or 'response'
# $dataref is a scalar ref to the data (\$data)
# $proto is a HTTP::Protocol object

sub filter_body {
    my ( $self, $type, $dataref, $proto ) = @_;

    # argument checking
    croak "Bad filter type: $type" if $type !~ /^re(?:quest|sponse)$/;

    my $message = $self->{$type};
    my $headers = $message->headers;

    # filter the body
    for ( @{ $self->{body}{$type} } ) {
        $_->[1]->( $dataref, $message, $proto ) if $_->[0]->();
    }
}

# standard proxy header filter (RFC 2616)
sub _proxy_headers_filter {
    my ( $headers, $message ) = @_;

    # the Via: header
    my $via = $message->protocol() || '';
    if ( $via =~ s!HTTP/!! ) {
        $via .= " " . hostname() . " (HTTP::Proxy/$VERSION)";
        $message->headers->header(
            Via => join ', ',
            $message->headers->header('Via') || (), $via
        );
    }

    # remove some headers
    for (

        # LWP::UserAgent Client-* headers
        qw( Client-Aborted Client-Bad-Header-Line Client-Date Client-Junk
        Client-Peer Client-Request-Num Client-Response-Num
        Client-SSL-Cert-Issuer Client-SSL-Cert-Subject Client-SSL-Cipher
        Client-SSL-Warning Client-Transfer-Encoding Client-Warning ),

        # hop-by-hop headers(for now)
        qw( Connection Keep-Alive TE Trailers Transfer-Encoding Upgrade
        Proxy-Connection Proxy-Authenticate Proxy-Authorization )
      )
    {
        $message->headers->remove_header($_);
    }
}


=item log( $level, $prefix, $message )

Adds $message at the end of C<logfh>, if $level is greater than C<verbose>,
the log() method also prints a timestamp.

The output looks like:

    [Thu Dec  5 12:30:12 2002] $prefix $message

If $message is a multiline string, several log lines will be output,
each starting with $prefix.

=cut

sub log {
    my $self  = shift;
    my $level = shift;
    my $fh    = $self->logfh;

    return if $self->verbose < $level;

    my ( $prefix, $msg ) = ( @_, '' );
    my @lines = split /\n/, $msg;
    @lines = ('') if not @lines;

    flock( $fh, LOCK_EX );
    print $fh "[" . localtime() . "] $prefix $_\n" for @lines;
    flock( $fh, LOCK_UN );
}

=back

=cut

=head1 BUGS

I've heard that some Unix systems do not support calling accept() in a
child process when the socket was opened by the parent (especially
when several child process accept() at the same time).

Expect the prefork system to change.

=head1 TODO

* Provide an interface for logging.

* Provide control over the proxy through special URLs

=head1 AUTHOR

Philippe "BooK" Bruhat, E<lt>book@cpan.orgE<gt>.

=head1 THANKS

Many people helped me during the development of this module, either on
mailing-lists, irc, or over a beer in a pub...

So, in no particular order, thanks to Michael Schwern (testing while forking),
Eric 'echo' Cholet (preforked processes).

=head1 COPYRIGHT

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

1;
