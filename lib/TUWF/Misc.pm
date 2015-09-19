
package TUWF::Misc;
# Yeah, just put all miscellaneous functions in one module!
# Geez, talk about being sloppy...

use strict;
use warnings;
use Carp 'croak';
use Exporter 'import';
use Encode 'encode_utf8';
use Scalar::Util 'looks_like_number';


our $VERSION = '0.2';
our @EXPORT = ('formValidate', 'mail');
our @EXPORT_OK = ('uri_escape', 'kv_validate');


sub uri_escape {
  local $_ = encode_utf8 shift;
  s/([^A-Za-z0-9._~-])/sprintf '%%%02X', ord $1/eg;
  return $_;
}


sub kv_validate {
  my($sources, $templates, $params) = @_;

  my @err;
  my %ret;

  for my $f (@$params) {
    my $src = (grep $f->{$_}, keys %$sources)[0];
    my @values = $sources->{$src}->($f->{$src});
    @values = ($values[0]) if !$f->{multi};

    # check each value and add it to %ret
    for (@values) {
      my $errfield = _validate($_, $templates, $f);
      next if !$errfield;
      push @err, [ $f->{$src}, $errfield, $f->{$errfield} ];
      last;
    }
    $ret{$f->{$src}} = $f->{multi} ? \@values : $values[0];

    # check mincount/maxcount
    push @err, [ $f->{$src}, 'mincount', $f->{mincount} ] if $f->{mincount} && @values < $f->{mincount};
    push @err, [ $f->{$src}, 'maxcount', $f->{maxcount} ] if $f->{maxcount} && @values > $f->{maxcount};
  }

  $ret{_err} = \@err if @err;
  return \%ret;
}


# Internal function used by kv_validate, checks one value on the validation
# rules, the name of the failed rule on error, undef otherwise
sub _validate { # value, \%templates, \%rules
  my($v, $t, $r) = @_;

  croak "Template $r->{template} not defined." if $r->{template} && !$t->{$r->{template}};
  $r->{required}++ if not exists $r->{required};
  $r->{rmwhitespace}++ if not exists $r->{rmwhitespace};

  # remove whitespace
  if($v && $r->{rmwhitespace}) {
    $_[0] =~ s/\r//g;
    $_[0] =~ s/^[\s\n]+//;
    $_[0] =~ s/[\s\n]+$//;
    $v = $_[0]
  }

  # empty
  if(!defined($v) || length($v) < 1) {
    return 'required' if $r->{required};
    $_[0] = $r->{default} if exists $r->{default};
    return undef;
  }

  # length
  return 'minlength' if $r->{minlength} && length $v < $r->{minlength};
  return 'maxlength' if $r->{maxlength} && length $v > $r->{maxlength};
  # min/max
  return 'min'       if defined($r->{min}) && (!looks_like_number($v) || $v < $r->{min});
  return 'max'       if defined($r->{max}) && (!looks_like_number($v) || $v > $r->{max});
  # enum
  return 'enum'      if $r->{enum} && !grep $_ eq $v, @{$r->{enum}};
  # regex
  return 'regex'     if $r->{regex} && (ref($r->{regex}) eq 'ARRAY' ? ($v !~ m/$r->{regex}[0]/) : ($v !~  m/$r->{regex}/));
  # template
  return 'template'  if $r->{template} && _validate($_[0], $t, $t->{$r->{template}});
  # function
  return 'func'      if $r->{func} && (ref($r->{func}) eq 'ARRAY' ? !$r->{func}[0]->($_[0]) : !$r->{func}->($_[0]));
  # passed validation
  return undef;
}




sub formValidate {
  my($self, @fields) = @_;
  return kv_validate(
    { post   => sub { $self->reqPost(shift)   },
      get    => sub { $self->reqGet(shift)    },
      param  => sub { $self->reqParam(shift)  },
      cookie => sub { $self->reqCookie(shift) },
    }, $self->{_TUWF}{validate_templates} || {},
    \@fields
  );
}



# A simple mail function, body and headers as arguments. Usage:
#  $self->mail('body', header1 => 'value of header 1', ..);
sub mail {
  my $self = shift;
  my $body = shift;
  my %hs = @_;

  croak "No To: specified!\n" if !$hs{To};
  croak "No Subject: specified!\n" if !$hs{Subject};
  $hs{'Content-Type'} ||= 'text/plain; charset=\'UTF-8\'';
  $hs{From} ||= $self->{_TUWF}{mail_from};
  $body =~ s/\r?\n/\n/g;

  my $mail = '';
  foreach (keys %hs) {
    $hs{$_} =~ s/[\r\n]//g;
    $mail .= sprintf "%s: %s\n", $_, $hs{$_};
  }
  $mail .= sprintf "\n%s", $body;

  if(open(my $mailer, '|-:utf8', "$self->{_TUWF}{mail_sendmail} -t -f '$hs{From}'")) {
    print $mailer $mail;
    croak "Error running sendmail ($!)"
      if !close($mailer);
  } else {
    croak "Error opening sendail ($!)";
  }
}


1;
