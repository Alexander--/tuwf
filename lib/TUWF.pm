# TUWF.pm - the core module for TUWF
#  The Ultimate Website Framework

package TUWF;

use strict;
use warnings;
use Carp 'croak';

our $VERSION = '1.1';


# Store the object in a global variable for some functions that don't get it
# passed as an argument. This will break when:
#  - using a threaded environment (threading sucks anyway)
#  - handling multiple requests asynchronously (which this framework can't do)
#  - handling multiple sites in the same perl process. This may be useful in
#    a mod_perl environment, which we don't support.
our $OBJ = bless {
  _TUWF => {
    route_handlers => [],
    hooks => {
      before => [],
      after => [],
    },
    # defaults
    mail_from => '<noreply-yawf@blicky.net>',
    mail_sendmail => '/usr/sbin/sendmail',
    max_post_body => 10*1024*1024, # 10MB
    error_400_handler => \&_error_400,
    error_404_handler => \&_error_404,
    error_405_handler => \&_error_405,
    error_413_handler => \&_error_413,
    error_500_handler => \&_error_500,
    log_format => sub {
      my($self, $uri, $msg) = @_;
      sprintf "[%s] %s -> %s\n", scalar localtime(), $uri, $msg;
    },
    validate_templates => {},
    # No particular selection of MIME types
    mime_types => {qw{
      7z     application/x-7z-compressed
      atom   application/atom+xml
      bmp    image/bmp
      css    text/css
      gif    image/gif
      htm    text/html
      html   text/html
      ico    image/x-icon
      jpeg   image/jpeg
      jpg    image/jpeg
      js     application/javascript
      json   application/json
      mp3    audio/mpeg
      mp4    video/mp4
      mp4v   video/mp4
      mpg4   video/mp4
      oga    audop/ogg
      ogg    audio/ogg
      pdf    application/pdf
      png    image/png
      rar    application/x-rar-compressed
      rss    application/rss+xml
      svg    image/svg+xml
      tar    application/x-tar
      txt    text/plain
      webm   video/webm
      xhtml  text/html
      xml    application/xml
      xsd    application/xml
      xsl    application/xml
      zip    application/zip
    }},
    mime_default => 'text/plain',
    http_server_port => $ENV{TUWF_HTTP_SERVER_PORT}||3000,
  }
}, 'TUWF::Object';


sub import {
  my $self = shift;
  my $pack = caller();
  # Always export 'tuwf'. This can still be excluded with a '!tuwf' in @_
  my @arg = ('tuwf', @_);

  # import requested functions from TUWF submodules
  croak $@ if !eval "package $pack; import TUWF::func \@arg; 1";
}


# get or set TUWF configuration variables
sub set {
  return $OBJ->{_TUWF}{$_[0]} if @_ == 1;
  $OBJ->{_TUWF} = { %{$OBJ->{_TUWF}}, @_ };
}


sub run {
  # load the database module if requested
  $OBJ->_load_module('TUWF::DB') if $OBJ->{_TUWF}{db_login};

  # install a warning handler to write to the log file
  $SIG{__WARN__} = sub { $TUWF::OBJ->log($_) for @_; };

  # load optional modules
  require Time::HiRes if $OBJ->debug || $OBJ->{_TUWF}{log_slow_pages};

  # initialize DB connection
  $OBJ->dbInit if $OBJ->{_TUWF}{db_login};

  # In a FastCGI environment, STDIN will be a listen socket; getpeername() will
  # return a ENOTCONN on those, giving us a reliably way to differentiate
  # between CGI (env vars), FastCGI (STDIN socket), and others.
  my(undef) = (getpeername \*STDIN);
  my $isfastcgi = $!{ENOTCONN};

  # plain old CGI
  if($ENV{GATEWAY_INTERFACE} && $ENV{GATEWAY_INTERFACE} =~ /CGI/i) {
    $OBJ->_handle_request;

  # otherwise, test for FastCGI
  } elsif($isfastcgi) {
    require FCGI;
    import FCGI;
    my $r = FCGI::Request();
    $OBJ->{_TUWF}{fcgi_req} = $r;
    while($r->Accept() >= 0) {
      $OBJ->_handle_request;
      $r->Finish();
    }

  # otherwise, run our own HTTP server
  } else {
    require HTTP::Server::Simple;
    require HTTP::Server::Simple::CGI::Environment;
    $OBJ->{_TUWF}{http} = 1;
    my $h = TUWF::http->new($OBJ->{_TUWF}{http_server_port});
    $h->run;
  }

  # close the DB connection
  $OBJ->dbDisconnect if $OBJ->{_TUWF}{db_login};
}


# Maps URLs to handlers (legacy)
sub register {
  my $a = \@_;
  for my $i (0..$#$a/2) {
    push @{$OBJ->{_TUWF}{route_handlers}},
      qr{^(?:GET|POST|HEAD) /$a->[$i*2]$},
      sub { $a->[$i*2+1]->($OBJ, @{$OBJ->{_TUWF}{captures_pos}}) }
  }
}


# Register router handlers
sub any {
  my($methods, $path, $sub) = @_;
  croak 'Methods argument in route registration must be an array' if ref $methods ne 'ARRAY';
  croak 'Path argument in route registration must be a string or regex' if ref $path && ref $path ne 'Regexp';
  croak 'Subroutine argument in route registration must be a code reference' if ref $sub ne 'CODE';
  my $methods_re = '(?:' . join('|', map uc, @$methods). ')';
  my $path_re = ref $path eq 'Regexp' ? $path : quotemeta $path;
  push @{$OBJ->{_TUWF}{route_handlers}}, qr{^$methods_re $path_re$}, $sub;
}

sub get     ($&) { any ['get','head'], @_ }
sub post    ($&) { any ['post'      ], @_ }
sub del     ($&) { any ['delete'    ], @_ }
sub options ($&) { any ['options'   ], @_ }
sub put     ($&) { any ['put'       ], @_ }
sub patch   ($&) { any ['patch'     ], @_ }


sub hook ($&) {
  my($hook, $sub) = @_;
  croak "Unknown hook: $hook" if $hook ne 'before' && $hook ne 'after';
  croak 'Hooks expect a subroutine as second argument' if ref $sub ne 'CODE';
  push @{$OBJ->{_TUWF}{hooks}{$hook}}, $sub;
}


# Load modules
sub load {
  $OBJ->_load_module($_) for (@_);
}

# Load modules, recursively
# All submodules should be under the same directory in @INC
sub load_recursive {
  my $rec;
  $rec = sub {
    my($d, $f, $m) = @_;
    for my $s (glob "\"$d/$f/*\"") {
      $OBJ->_load_module("${m}::$1") if -f $s && $s =~ /([^\/]+)\.pm$/;
      $rec->($d, "$f/$1", "${m}::$1") if -d $s && $s =~ /([^\/]+)$/;
    }
  };
  for my $m (@_) {
    (my $f = $m) =~ s/::/\//g;
    my $d = (grep +(-d "$_/$f" or -s "$_/$f.pm"), @INC)[0];
    croak "No module or submodules of '$m' found" if !$d;
    $OBJ->_load_module($m) if -s "$d/$f.pm";
    $rec->($d, $f, $m) if -d "$d/$f";
  }
}


sub _error_400 { _very_simple_page(400, '400 - Bad Request', 'Only UTF-8 encoded data is accepted.<br><small>Stop trying to hack me!</small>') }
sub _error_404 {
  _very_simple_page(404, '404 - Page Not Found', q{
    Whatever it is you were looking for, this probably isn't it.
    <br><small>Unless you were looking for an error page, in which case:
    Congratulations!</small>
  });
}
sub _error_405 { _very_simple_page(405, '405 - Method not allowed', 'Or at least, this isn\'t one of the HTTP methods that I was expecting!') }
sub _error_413 {
  _very_simple_page(413, '413 - Request Entity Too Large', q{
    That's an odd way of saying that you were probably trying to upload a large
    file. Too large, in fact, for the server to handle. If you believe this
    error to be mistaken, you can ask the site admin to increase the maximum
    allowed upload size.
  });
}
sub _error_500 {
  _very_simple_page(500, '500 - Extraterrestrial Server Error', q{
    Ouch! Something went wrong on the server. Perhaps a misconfiguration,
    perhaps a bug, or perhaps just a temporary issue caused by regular
    maintenance or maybe even alien interference.  Details of this error have
    been written to a log file. If the issue persists, please contact the site
    admin to let them know that they might have some fixing to do.
  });
}

# a super simple page for error messages
sub _very_simple_page {
  my($code, $title, $msg) = @_;
  $OBJ->resInit;
  $OBJ->resStatus($code);
  $OBJ->resHeader(Allow => 'GET, HEAD, POST') if $code == 405; # XXX: not accurate, should get this from the route list.
  my $fd = $OBJ->resFd;
  # CSS based on http://bettermotherfuckingwebsite.com/
  print $fd <<__;
<!DOCTYPE html>
<html>
<head>
 <meta name="viewport" content="width=device-width, initial-scale=1">
 <style type="text/css">
  body { margin:40px auto; max-width:700px; line-height:1.6; font-size:18px; color:#444; padding:0 10px }
  h1 { line-height:1.2 }
 </style>
 <title>$title</title>
</head>
<body>
 <h1>$title</h1>
 <p>$msg</p>
</body>
</html>
__
}



# A 'redirection' namespace for all functions exported by TUWF submodules.
# This trick avoids having to write our own sophisticated import() function
package TUWF::func;

use Exporter 'import';

# don't 'use' the submodules, since they may export TUWF object methods by
# default. We're only interested in their non-method functions, which are all
# in @EXPORT_OK.
BEGIN {
  require TUWF::DB;
  require TUWF::Misc;
  require TUWF::XML;
  import TUWF::DB   @TUWF::DB::EXPORT_OK;
  import TUWF::Misc @TUWF::Misc::EXPORT_OK;
  import TUWF::XML  @TUWF::XML::EXPORT_OK;
}
our @EXPORT_OK = (
  @TUWF::DB::EXPORT_OK,
  @TUWF::Misc::EXPORT_OK,
  @TUWF::XML::EXPORT_OK
);
our %EXPORT_TAGS = %TUWF::XML::EXPORT_TAGS;
our @EXPORT = ('tuwf');

sub tuwf() { $TUWF::OBJ }



# The namespace which inherits all functions to be available in the global
# object.
package TUWF::Object;

use TUWF::Response;
use TUWF::Request;
use TUWF::Misc;

require Carp; # but don't import()
our @CARP_NOT = ('TUWF');


sub _load_module {
  my($self, $module) = @_;
  Carp::croak $@ if !eval "use $module; 1";
}


# Handles a request (sounds pretty obvious to me...)
sub _handle_request {
  my $self = shift;

  my $start = [Time::HiRes::gettimeofday()] if $self->debug || $OBJ->{_TUWF}{log_slow_pages};

  # put everything in an eval to catch any error, even
  # those caused by a TUWF core module
  my $eval = eval {
    # initialze response
    $self->resInit();

    # initialize TUWF::XML
    TUWF::XML->new(
      write  => sub { print { $self->resFd } $_ for @_ },
      pretty => $self->{_TUWF}{xml_pretty},
      default => 1,
    );

    # initialize request
    my $err = $self->reqInit();
    if($err) {
      warn "Client sent non-UTF-8-encoded data. Generating HTTP 400 response.\n" if $err eq 'utf8';
      warn "Client sent an invalid JSON object. Generating HTTP 400 response.\n" if $err eq 'json';
      $self->{_TUWF}{error_400_handler}->($self) if $err eq 'utf8' || $err eq 'json';
      $self->{_TUWF}{error_405_handler}->($self) if $err eq 'method';
      $self->{_TUWF}{error_413_handler}->($self) if $err eq 'maxpost';
      return 1;
    }

    # make sure our DB connection is still there and start a new transaction
    $self->dbCheck() if $self->{_TUWF}{db_login};

    # call pre request handler, if any
    return 1 if $self->{_TUWF}{pre_request_handler} && !$self->{_TUWF}{pre_request_handler}->($self);

    # run 'before' hooks
    for (@{$self->{_TUWF}{hooks}{before}}) {
      return 1 if !$_->();
    }

    # find the handler
    my $loc = sprintf '%s %s', $self->reqMethod(), $self->reqPath();
    study $loc;
    my $han = $self->{_TUWF}{error_404_handler};
    $self->{_TUWF}{captures_pos} = [];
    $self->{_TUWF}{captures_named} = {};
    my $handlers = $self->{_TUWF}{route_handlers};
    for (@$handlers ? 0..$#$handlers/2 : ()) {
      if($loc =~ $handlers->[$_*2]) {
        $self->{_TUWF}{captures_pos} = [
          map defined $-[$_] ? substr $loc, $-[$_], $+[$_]-$-[$_] : undef, 1..$#-
        ];
        $self->{_TUWF}{captures_named} = { %+ };
        $han = $handlers->[$_*2+1];
        last;
      }
    }

    # execute handler
    $han->($self);

    # execute post request handler, if any
    $self->{_TUWF}{post_request_handler}->($self) if $self->{_TUWF}{post_request_handler};
    1;
  };
  my $evalerr = $@;

  # always run 'after' hooks
  my $cleanup = eval {
    $_->() for (@{$self->{_TUWF}{hooks}{after}});
    1;
  };
  my $cleanuperr = $@;

  # commit changes if everything went okay
  my $commit = eval {
    if($eval && $cleanup && $self->{_TUWF}{db_login}) {
      $self->dbCommit;
    }
    1;
  };
  my $commiterr = $@;

  # error handling
  if(!$eval || !$cleanup || !$commit) {
    chomp( my $err = $evalerr || $cleanuperr || $commiterr );

    # act as if the changes to the DB never happened
    warn $@ if $self->{_TUWF}{db_login} && !eval { $self->dbRollBack; 1 };

    # Call the error_500_handler
    # The handler should manually call dbCommit if it makes any changes to the DB
    my $eval500 = eval {
      $self->resInit;
      $self->{_TUWF}{error_500_handler}->($self, $err);
      1;
    };
    if(!$eval500) {
      chomp( my $m = $@ );
      warn "Error handler died as well, something is seriously wrong with your code. ($m)\n";
      TUWF::_error_500($self, $err);
    }

    # write detailed information about this error to the log
    $self->log(
      "FATAL ERROR!\n".
      "HTTP Request Headers:\n".
      join('', map sprintf("  %s: %s\n", $_, $self->reqHeader($_)), $self->reqHeader).
      "POST dump:\n".
      join('', map sprintf("  %s: %s\n", $_, join "\n    ", $self->reqPosts($_)), $self->reqPosts).
      "Error:\n  $err\n"
    );
  }

  # finalize response (flush output, etc)
  warn $@ if !eval { $self->resFinish; 1 };

  # log debug information in the form of:
  # >  12ms (SQL:  8ms,  2 qs) for http://beta.vndb.org/v10
  my $time = Time::HiRes::tv_interval($start)*1000 if $self->debug || $self->{_TUWF}{log_slow_pages};
  if($self->debug || ($self->{_TUWF}{log_slow_pages} && $self->{_TUWF}{log_slow_pages} < $time)) {
    # SQL stats (don't count the ping and commit as queries, but do count their time)
    my($sqlt, $sqlc) = (0, 0);
    if($self->{_TUWF}{db_login}) {
      $sqlc = grep $_->[0] ne 'ping/rollback' && $_->[0] ne 'commit', @{$self->{_TUWF}{DB}{queries}};
      $sqlt += $_->[2]*1000 for (@{$self->{_TUWF}{DB}{queries}});
    }

    $self->log(sprintf('%4dms (SQL:%4dms,%3d qs)', $time, $sqlt, $sqlc));
  }
}


# convenience function
sub debug {
  return shift->{_TUWF}{debug};
}


sub capture {
  my($self, $key) = @_;
  $key =~ /^[0-9]+$/
    ? $self->{_TUWF}{captures_pos}[$key-1]
    : $self->{_TUWF}{captures_named}{$key};
}


# writes a message to the log file. date, time and URL are automatically added
sub log {
  my($self, $msg) = @_;

  # temporarily disable the warnings-to-log, to avoid infinite recursion if
  # this function throws a warning.
  local $SIG{__WARN__} = undef;

  chomp $msg;
  $msg =~ s/\n/\n  | /g;
  $msg = $self->{_TUWF}{log_format}->($self, $self->{_TUWF}{Req} ? $self->reqURI : '[init]', $msg);

  if($self->{_TUWF}{logfile} && open my $F, '>>:utf8', $self->{_TUWF}{logfile}) {
    flock $F, 2;
    seek $F, 0, 2;
    print $F $msg;
    flock $F, 4;
    close $F;
  }
  # Also always dump stuff to STDERR if we're running a standalone HTTP server.
  warn $msg if $self->{_TUWF}{http};
}



# Minimal subclass of HTTP::Server::Simple with CGI environment variables.
package TUWF::http;

use strict;
use warnings;
our @ISA = qw{
    HTTP::Server::Simple
    HTTP::Server::Simple::CGI::Environment
};

sub accept_hook { shift->setup_environment }
sub setup       { shift->setup_environment_from_metadata(@_) }

sub handler {
  shift->setup_server_url;
  $TUWF::OBJ->_handle_request;
};


1;

