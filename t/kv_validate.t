#!/usr/bin/perl

use strict;
use warnings;

my @tests;
my %templates;
BEGIN{@tests=(
  # definition of a single field
  # input parameters
  # expected output

  # required / default
  { param => 'name' },
  [],
  { name => undef, _err => [[ 'name', 'required', 1 ]] },

  { param => 'name' },
  [ name => '' ],
  { name => '', _err => [[ 'name', 'required', 1 ]] },

  { param => 'name', required => 'x' },
  [ name => '' ],
  { name => '', _err => [[ 'name', 'required', 'x' ]] },

  { param => 'name', required => 0 },
  [ name => '' ],
  { name => '' },

  { param => 'name', required => 0, default => undef },
  [ name => '' ],
  { name => undef },

  { param => 'name' },
  [ name => '0' ],
  { name => '0' },

  # rmwhitespace
  { param => 'name' },
  [ name => " Va\rlid \n " ],
  { name => 'Valid' },

  { param => 'name', rmwhitespace => 0 },
  [ name => " Va\rlid \n " ],
  { name => " Va\rlid \n " },

  { param => 'name' },
  [ name => '  ' ],
  { name => '', _err => [[ 'name', 'required', 1 ]] },

  # min / max
  { param => 'age', min => 0, max => 0 },
  [ age => 0 ],
  { age => 0 },

  { param => 'age', min => 0, max => 0 },
  [ age => 1 ],
  { age => 1, _err => [[ 'age', 'max', 0 ]] },

  { param => 'age', min => 0, max => 0 },
  [ age => 0.5 ],
  { age => 0.5, _err => [[ 'age', 'max', 0 ]] },

  { param => 'age', min => 0, max => 0 },
  [ age => -1 ],
  { age => -1, _err => [[ 'age', 'min', 0 ]] },

  { param => 'age', min => 0, max => 1000 },
  [ age => '1e3' ],
  { age => '1e3' },

  { param => 'age', min => 0, max => 1000 },
  [ age => '1e4' ],
  { age => '1e4', _err => [[ 'age', 'max', 1000 ]] },

  { param => 'age', min => 0, max => 0 },
  [ age => 'x' ],
  { age => 'x', _err => [[ 'age', 'min', 0 ]] },

  # minlength / maxlength
  { param => 'msg', minlength => 2 },
  [ msg => 'ab' ],
  { msg => 'ab' },

  { param => 'msg', minlength => 2 },
  [ msg => 'a' ],
  { msg => 'a', _err => [[ 'msg', 'minlength', 2 ]] },

  { param => 'msg', maxlength => 2 },
  [ msg => 'ab' ],
  { msg => 'ab' },

  { param => 'msg', maxlength => 2 },
  [ msg => 'abc' ],
  { msg => 'abc', _err => [[ 'msg', 'maxlength', 2 ]] },

  { param => 'msg', minlength => 2 },
  [ msg => '  a  ' ],
  { msg => 'a', _err => [[ 'msg', 'minlength', 2 ]] },

  { param => 'msg', maxlength => 2 },
  [ msg => '     ab     ' ],
  { msg => 'ab' },

  # enum
  { param => 'type', enum => ['a'..'z'] },
  [ type => 'a' ],
  { type => 'a' },

  { param => 'type', enum => ['a'..'z'] },
  [ type => 'y' ],
  { type => 'y' },

  { param => 'type', enum => ['a'..'z'] },
  [ type => 'Y' ],
  { type => 'Y', _err => [[ 'type', 'enum', ['a'..'z'] ]] },

  # multi / maxcount / mincount
  { param => 'board' },
  [ board => 1, board => 2 ],
  { board => 1 }, # Not sure I like this behaviour.

  { param => 'board', multi => 1 },
  [ board => 1, board => 2 ],
  { board => [1,2] },

  { param => 'board', multi => 1 },
  [ board => 1 ],
  { board => [1] },

  { param => 'board', multi => 1 },
  [ board => '' ],
  { board => [''], _err => [[ 'board', 'required', 1 ]] },

  { param => 'board', multi => 1, min => 1 },
  [ board => 0 ],
  { board => [0], _err => [[ 'board', 'min', 1 ]] },

  { param => 'board', multi => 1, maxcount => 1 },
  [ board => 1 ],
  { board => [1] },

  { param => 'board', multi => 1, maxcount => 1 },
  [ board => 1, board => 2 ],
  { board => [1,2], _err => [[ 'board', 'maxcount', 1 ]] },

  { param => 'board', multi => 1, mincount => 1 },
  [ board => 1 ],
  { board => [1] },

  { param => 'board', multi => 1, mincount => 2 },
  [ board => 1 ],
  { board => [1], _err => [[ 'board', 'mincount', 2 ]] },

  # regex
  do { my $r = qr/^[0-9a-f]{3}$/i; (
  { param => 'hex', regex => $r },
  [ hex => '0F3' ],
  { hex => '0F3' },

  { param => 'hex', regex => $r },
  [ hex => '0134' ],
  { hex => '0134', _err => [[ 'hex', 'regex', $r ]] },

  { param => 'hex', regex => $r },
  [ hex => '03X' ],
  { hex => '03X', _err => [[ 'hex', 'regex', $r ]] },

  { param => 'hex', regex => [$r, 1,2,3] },
  [ hex => '03X' ],
  { hex => '03X', _err => [[ 'hex', 'regex', [$r, 1,2,3] ]] },
  )},

  # func
  do { my $f = sub { $_[0] =~ y/a-z/A-Z/; $_[0] =~ /^X/ }; (
  { param => 't', func => $f },
  [ t => 'xyz' ],
  { t => 'XYZ' },

  { param => 't', func => $f },
  [ t => 'zyx' ],
  { t => 'ZYX', _err => [[ 't', 'func', $f ]] },

  { param => 't', func => [$f,1,2,3] },
  [ t => 'zyx' ],
  { t => 'ZYX', _err => [[ 't', 'func', [$f,1,2,3] ]] },
  )},

  # template
  do {
    $templates{hex} = { regex => qr/^[0-9a-f]+$/i };
    $templates{crc32} = { template => 'hex', minlength => 8, maxlength => 8 };
  ()},
  { param => 'crc', template => 'hex' },
  [ crc => '12345678' ],
  { crc => '12345678' },
  
  { param => 'crc', template => 'crc32' },
  [ crc => '12345678' ],
  { crc => '12345678' },

  { param => 'crc', template => 'hex' },
  [ crc => '12x45678' ],
  { crc => '12x45678', _err => [[ 'crc', 'template', 'hex' ]] },

  { param => 'crc', template => 'crc32' },
  [ crc => '123456789' ],
  { crc => '123456789', _err => [[ 'crc', 'template', 'crc32' ]] },
)}

use Test::More tests => 1+@tests/3;

BEGIN { use_ok('TUWF::Misc', 'kv_validate') };

sub getfield {
  my($n, $f) = @_;
  map +($f->[$_*2] eq $n ? $f->[$_*2+1] : ()), @$f ? 0..$#$f/2 : ();
}

for my $i (0..$#tests/3) {
  my($fields, $params, $exp) = ($tests[$i*3], $tests[$i*3+1], $tests[$i*3+2]);
  is_deeply(kv_validate({ param => sub { getfield($_[0], $params) } }, \%templates, [$fields]), $exp, 'Test '.($i+1));
}
