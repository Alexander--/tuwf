# YAWF.pm - the core module for YAWF
#   Yet Another Website Framework
#   Yorhels Awesome Website Framework

package YAWF;

use strict;
use warnings;

# Store the object in a global variable for some functions that don't get it
# passed as an argument. This will break when:
#  - using a threaded environment (threading sucks anyway)
#  - handling multiple requests asynchronously (which this framework can't do)
#  - handling multiple sites in the same perl process. This may be useful in
#    a FastCGI or mod_perl environment, so need to find a fix for that >.>
our $OBJ;
my @handlers;


# The holy init() function
sub init {
  my %o = (
    error_500_handler => \&YAWF::DefaultHandlers::error_500,
    error_404_handler => \&YAWF::DefaultHandlers::error_404,
    @_
  );
  die "No namespace argument specified!" if !$o{namespace};
  die "db_login argument required!" if !$o{db_login};

  # create object
  $OBJ = bless {
    _YAWF => \%o,
    $o{object_data} && ref $o{object_data} eq 'HASH' ? %{ delete $o{object_data} } : (),
  }, 'YAWF::Object';

  # install a warning handler to write to the log file
  $SIG{__WARN__} = \&log_warning;

  # load optional modules
  require Time::HiRes if $OBJ->debug;

  # load the modules
  $OBJ->load_modules;

  # initialize DB connection
  $OBJ->dbInit;

  # plain old CGI
  if($ENV{GATEWAY_INTERFACE} && $ENV{GATEWAY_INTERFACE} =~ /CGI/i) {
    $OBJ->handle_request;
  }
  # otherwise, assume a FastCGI environment
  else {
    require FCGI;
    import FCGI;
    my $r = FCGI::Request();
    while($r->Accept() >= 0) {
      $OBJ->handle_request;
      $r->Finish();
    }
  }

  # close the DB connection
  $OBJ->dbDisconnect;
}


# Maps URLs to handlers
sub register {
  push @handlers, @_;
}


# Writes warning messages to the log file (if there is a log file)
sub log_warning {
  if($YAWF::OBJ->{_YAWF}{logfile} && open my $F, '>>', $YAWF::OBJ->{_YAWF}{logfile}) {
    flock $F, 2;
    seek $F, 0, 2;
    while(local $_ = shift) {
      chomp;
      printf $F "[%s] %s: %s\n", scalar localtime(), $OBJ->reqFullURI||'[init]', $_;
    }
    flock $F, 4;
    close $F;
  } else {
    warn @_;
  }
}




# The namespace which inherits all functions to be available in the global
# object. These functions are not inherited by the main YAWF namespace.
package YAWF::Object;

use YAWF::Response;
use YAWF::Request;
use YAWF::DB;


# This function will load all site modules and import the exported functions
sub load_modules {
  my $s = shift;
  (my $f = $s->{_YAWF}{namespace}) =~ s/::/\//g;
  for my $p (@INC) {
    for (glob $p.'/'.$f.'/{DB,Util,Handler}/*.pm') {
      (my $m = $_) =~ s{^\Q$p/}{};
      $m =~ s/\.pm$//;
      $m =~ s{/}{::}g;
      # the following is pretty much equivalent to eval "use $m";
      require $_;
      no strict 'refs';
      "$m"->import if *{"${m}::import"}{CODE};
    }
  }
}


# Handles a request (sounds pretty obvious to me...)
sub handle_request {
  my $self = shift;

  # put everything in an eval to catch any error, even
  # those caused by a YAWF core module
  eval { 

    # initialize request and response objects
    $self->reqInit();
    $self->resInit();
    
    # make sure our DB connection is still there and start a new transaction
    $self->dbCheck();

    # call pre request handler, if any
    $self->{_YAWF}{pre_request_handler}->($self) if $self->{_YAWF}{pre_request_handler};

    # find the handler
    my $loc = ''; #$self->reqLocation;
    study $loc;
    my $han = $self->{_YAWF}{error_404_handler};
    for (@handlers ? 0..@handlers/2 : ()) {
      if($loc =~ /^$handlers[$_]$/) {
        $han = $handlers[$_+1];
        last;
      }
    }
    
    # execute handler
    my $ret = $han->($self);

    # give 404 page if the handler returned 404...
    if($ret && $ret eq '404') {
      $ret = $self->{_YAWF}{error_404_handler}->($self) if $han ne $self->{_YAWF}{error_404_handler};
      YAWF::DefaultHandlers::error_404($self) if $ret && $ret eq '404';
    }

    # execute post request handler, if any
    $self->{_YAWF}{post_request_handler}->($self) if $self->{_YAWF}{post_request_handler};

    # commit changes
    $self->dbCommit;
  };

  # error handling
  if($@) {
    # act as if the changes to the DB never happened
    eval { $self->dbRollBack; };
    warn $@ if $@;

    # Call the error_500_handler
    # The handler should manually call dbCommit if it makes any changes to the DB
    eval { $self->{_YAWF}{error_500_handler}->($self); };
    if($@) {
      chomp( my $m = $@ );
      warn "Error handler died as well, something is seriously wrong with your code. ($m)\n";
      YAWF::DefaultHandlers::error_500($self);
    }

    # some logging here...
  }

  # finalize response (flush output, etc)
  eval { $self->resFinish; };
  warn $@ if $@;

  if($self->debug) {
    # log some debug info here
  }
}


# convenience function
sub debug {
  return shift->{_YAWF}{debug};
}




# put the default handlers in a separate namespace
# (in case we do decide to use the HTML generator here)
package YAWF::DefaultHandlers;


# these are defaults, you really want to replace these boring pages
sub error_404 {
  my $s = shift;
  $s->resInit;
  $s->resStatus(404);
  very_simple_page($s, '404 - Page Not Found', 'The page you were looking for does not exist...');
}


# a *very* helpful error message :-)
sub error_500 {
  my $s = shift;
  $s->resInit;
  $s->resStatus(500);
  very_simple_page($s, '500 - Internal Server Error', 'Ooooopsie~, something went wrong!');
}


# and an equally beautiful page
sub very_simple_page {
  my($s, $title, $msg) = @_;
  my $fd = $s->resFd;
  print $fd <<__;
<!DOCTYPE html
  PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
 <title>$title</title>
</head>
<body>
 <h1>$title</h1>
 <p>$msg</p>
</body>
</html>
__
}



1;

