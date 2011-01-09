#!/usr/bin/perl


package TUWF::XML;


use strict;
use warnings;
use Exporter 'import';


our(@EXPORT_OK, %EXPORT_TAGS, @htmltags, @htmlexport, @xmlexport, @htmlbool);


BEGIN {
  # xhtml 1.0 tags
  @htmltags = qw|
    address blockquote div dl fieldset form h1 h2 h3 h4 h5 h6 noscript ol p pre ul
    a abbr acronym b bdo big br button cite code dfn em i img input kbd label Map
    object q samp Select small span strong Sub sup textarea tt var caption col
    colgroup table tbody td tfoot th thead Tr area base body dd del dt head ins
    legend li Link meta optgroup option param script style title
  |;

  # boolean (self-closing) tags
  @htmlbool = qw| hr br img input area base frame link param |;

  # functions to export
  @htmlexport = (@htmltags, qw| html lit txt tag end |);
  @xmlexport = qw| xml lit txt tag end |;

  # create the subroutines to map to the html tags
  no strict 'refs';
  for my $e (@htmltags) {
    *{__PACKAGE__."::$e"} = sub { _tag(1, $e, @_) }
  }

  @EXPORT_OK = (@htmlexport, @xmlexport, 'xml_escape');
  %EXPORT_TAGS = (
    html => \@htmlexport,
    xml  => \@xmlexport,
  );
};


# keeps track of the openend tags
my @lasttags;


# HTML escape, also does \n to <br /> conversion
sub xml_escape {
  local $_ = shift;
  return '' if !$_ && $_ ne '0';
  s/&/&amp;/g;
  s/</&lt;/g;
  s/>/&gt;/g;
  s/"/&quot;/g;
  s/\r?\n/<br \/>/g;
  return $_;
}


# output literal data (not HTML escaped)
sub lit {
  print { $TUWF::OBJ->resFd } $_ for @_;
}


# output text (HTML escaped)
sub txt {
  lit xml_escape $_ for @_;
}


# Output any XML or HTML tag.
# Arguments                           Output
#  'tagname'                           <tagname>
#  'tagname', id => "main"             <tagname id="main">
#  'tagname', '<bar>'                  <tagname>&lt;bar&gt;</tagname>
#  'tagname', id => 'main', '<bar>'    <tagname id="main">&lt;bar&gt;</tagname>
#  'tagname', id => 'main', undef      <tagname id="main" />
#  'tagname', undef                    <tagname />
sub _tag {
  my $indirect = shift; # called as tag() or as generated html function?
  my $name = shift;
  $name  =~ y/A-Z/a-z/ if $indirect;

  my $t = $TUWF::OBJ->{_TUWF}{xml_pretty} ? "\n".(' 'x(@lasttags*$TUWF::OBJ->{_TUWF}{xml_pretty})) : '';
  $t .= '<'.$name;
  $t .= ' '.(shift).'="'.xml_escape(shift).'"' while @_ > 1;

  push @_, undef if $indirect && !@_ && grep $name eq $_, @htmlbool;

  if(!@_) {
    $t .= '>';
    lit $t;
    push @lasttags, $name;
  } elsif(!defined $_[0]) {
    lit $t.' />';
  } else {
    lit $t.'>'.xml_escape(shift).'</'.$name.'>';
  } 
}
sub tag {
  _tag 0, @_;
}


# Ends the last opened tag
sub end() {
  my $l=pop @lasttags;
  lit "\n".(' 'x(@lasttags*$TUWF::OBJ->{_TUWF}{xml_pretty})) if $TUWF::OBJ->{_TUWF}{xml_pretty};
  lit '</'.$l.'>';
}


# Special function, this writes the XHTML 1.0 Strict doctype
# (other doctypes aren't supported at the moment)
sub html() {
  lit qq|<!DOCTYPE html
  PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">\n|;
  push @lasttags, 'html';
}


# Writes an xml header, doesn't open an <xml> tag, and doesn't need an
# end() either.
sub xml() {
  lit qq|<?xml version="1.0" encoding="UTF-8"?>\n|;
}


1;

