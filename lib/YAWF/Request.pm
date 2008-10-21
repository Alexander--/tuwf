
package YAWF::Request;

use strict;
use warnings;
use Encode 'decode_utf8';
use Exporter 'import';
use CGI::Cookie::XS;
use CGI::Minimal;

our @EXPORT = qw|
  reqInit reqParam reqSaveUpload reqCookie
  reqMethod reqHeader reqURI reqFullURI reqIP
|;


sub reqInit {
  my $self = shift;

  # reset and re-initialise some vars to make CGI::Minimal work in FastCGI
  CGI::Minimal::reset_globals;
  CGI::Minimal::allow_hybrid_post_get(1);
  CGI::Minimal::max_read_size(10*1024*1024); # allow 10MB of POST data

  my $cgi = CGI::Minimal->new();
  die "Truncated post request\n" if $cgi->truncated;

  $self->{_YAWF}{Req}{c} = $cgi;
}



# wrapper around CGI::Minimal's param(), only properly encodes everything to
# Perl's internal UTF-8 format, and returns an empty string on undef.
sub reqParam {
  my($s, $n) = @_;
  return wantarray
    ? map { defined $_ ? decode_utf8 $_ : '' } $s->{_YAWF}{Req}{c}->param($n)
    : defined $s->{_YAWF}{Req}{c}->param($n) ? decode_utf8 $s->{_YAWF}{Req}{c}->param($n) : '';
}


sub reqSaveUpload {
  my($s, $n, $f) = @_;
  open my $F, '>', $f or die "Unable to write to $f: $!";
  print $F $s->{_YAWF}{Req}{c}->param($n);
  close $F;
}


sub reqCookie {
  my $c = CGI::Cookie::XS->fetch;
  return $c && ref($c) eq 'HASH' && $c->{$_[1]} ? decode_utf8 $c->{$_[1]}[0] : '';
}


sub reqMethod {
  return ($ENV{REQUEST_METHOD}||'') =~ /post/i ? 'POST' : 'GET';
}


sub reqHeader {
  (my $v = uc $_[1]) =~ tr/-/_/;
  return $ENV{"HTTP_$v"}||'';
}


sub reqURI {
  (my $u = $ENV{REQUEST_URI}) =~ s{^/+}{};
  return $u;
}


# returns undef if the request isn't initialized yet
sub reqFullURI {
  return $ENV{HTTP_HOST} && defined $ENV{REQUEST_URI} ?
    $ENV{HTTP_HOST}.$ENV{REQUEST_URI}.($ENV{QUERY_STRING} ? '?'.$ENV{QUERY_STRING} : '')
    : undef;
}


sub reqIP {
  return $ENV{REMOTE_ADDR};
}


1;

