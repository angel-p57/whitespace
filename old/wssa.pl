#!/usr/bin/perl

use strict;
use warnings;
use bigint;
use Getopt::Std;

my $ENDMARK = '--end--';
my $SLIMIT_DEFAULT=10000;
my $CLEVEL_DEFAULT=3;
my @inst = ();
my @stack = ();
my @cstack = ();
my @heap = ();
my %labels = ();
my $ip = 0;
my $continue = 1;
my $skip = undef;
my $inum = 0;
my $bytes = 0;
my $step = 0;
my $stackhwm = 0;
my $ibuf = '';
my $codelevel;
my $slimit;
my $unlimited;

sub checkStack
{
  die "stack out of range\n" if @stack < $_[0];
}
sub updateHWM
{
  $stackhwm = @stack if $stackhwm < @stack;
}
sub wspush
{
  unshift @stack, shift;
  updateHWM();
}
sub wsdup
{
  unshift @stack, $stack[0];
  updateHWM();
}
sub wscopy
{
  my $pos = shift;
  checkStack($pos+1);
  unshift @stack, $stack[$pos];
  updateHWM();
}
sub wsswap
{
  @stack[0,1] = @stack[1,0];
}
sub wspop
{
  shift @stack;
}
sub wsslide
{
  my $num = shift;
  checkStack($num+1);
  splice @stack, 1, $num;
}
sub wsadd
{
  my $var = shift @stack;
  $stack[0] += $var;
}
sub wssub
{
  my $var = shift @stack;
  $stack[0] -= $var;
}
sub wsmul
{
  my $var = shift @stack;
  $stack[0] *= $var;
}
sub checkDivider($)
{
  die "0 divide exception occurred\n" if $_[0] == 0;
}
sub wsdiv
{
  my $var = shift @stack;
  checkDivider($var);
  $stack[0] -= $stack[0]%$var;
  $stack[0] /= $var;
}
sub wsmod
{
  my $var = shift @stack;
  checkDivider($var);
  $stack[0] %= $var;
}
sub checkHeapAddress($$)
{
  my ( $address, $doexpand ) = @_;
  die "negative address is not allowed\n"
    if $address < 0;
  return if $address <= $#heap;
  die "heap out of range\n" if !$doexpand;
  push @heap, (0)x($address-$#heap-1);
}
sub storeheap
{
  my ( $val, $addr ) = @_;
  checkHeapAddress($addr,1);
  $heap[$addr] = $val;
}
sub wsstor
{
  storeheap(splice @stack, 0, 2);
}
sub wsretr
{
  my $addr = shift @stack;
  checkHeapAddress($addr,0);
  unshift @stack, $heap[$addr];
}
sub wsmark
{
  my $label = shift;
  return if exists $labels{$label}->{'ip'};
  $labels{$label}->{'ip'} = $ip;
  undef $skip if defined $skip && $skip->{'to'} eq $label;
}
sub wsjump_common(@)
{
  my $label = shift;
  if ( exists $labels{$label}->{'ip'} )
  {
    $ip = $labels{$label}->{'ip'};
  }
  else
  {
    $skip = { 'to' => $label, 'from' => $ip };
  }
}
sub wscall
{
  unshift @cstack, $ip;
  wsjump_common(@_);
}
sub wsjump
{
  wsjump_common(@_);
}
sub wsjzero
{
  return unless 0 == shift @stack;
  wsjump_common(@_);
}
sub wsjneg
{
  return unless 0 > shift @stack;
  wsjump_common(@_);
}
sub wsret
{
  die "call stack is empty\n" unless @cstack;
  $ip = shift @cstack;
}
sub wsend
{
  $continue = 0;
}
sub wsputc
{
  my $val = shift @stack;
  my $c = chr $val;
  $c =~ /[^[:print:]\s]/
    and die "output non-printable character ( $val )\n";
  print $c;
}
sub wsputi
{
  print shift @stack;
}
sub fillbuffer
{
  $ibuf = <>;
  die "detected eof on input stream\n"
    unless defined $ibuf;
}
sub wsgetc
{
  fillbuffer() if $ibuf eq '';
  my $val = ord substr $ibuf, 0, 1, '';
  my $addr = shift @stack;
  storeheap($val, $addr);
}
sub wsgeti
{
  fillbuffer() if $ibuf eq '';
  $ibuf =~ /^\s*([-]?\d+)\s*$/
    or die "not integer data on input stream\n";
  my $val = 0+$1;
  $ibuf = '';
  my $addr = shift @stack;
  storeheap($val, $addr);
}
my %ops = (
  'push'  => { 'sub' => \&wspush,  'imp' => 's',  'code' => 's',  'arg' => 'int' },
  'dup'   => { 'sub' => \&wsdup,   'imp' => 's',  'code' => 'ns', 'arg' => 'void', 'stackfreq' => 1 },
  'copy'  => { 'sub' => \&wscopy,  'imp' => 's',  'code' => 'ts', 'arg' => 'uint' },
  'swap'  => { 'sub' => \&wsswap,  'imp' => 's',  'code' => 'nt', 'arg' => 'void', 'stackfreq' => 2 },
  'pop'   => { 'sub' => \&wspop,   'imp' => 's',  'code' => 'nn', 'arg' => 'void', 'stackfreq' => 1 },
  'slide' => { 'sub' => \&wsslide, 'imp' => 's',  'code' => 'tn', 'arg' => 'uint' },
  'add'   => { 'sub' => \&wsadd,   'imp' => 'ts', 'code' => 'ss', 'arg' => 'void', 'stackfreq' => 2 },
  'sub'   => { 'sub' => \&wssub,   'imp' => 'ts', 'code' => 'st', 'arg' => 'void', 'stackfreq' => 2 },
  'mul'   => { 'sub' => \&wsmul,   'imp' => 'ts', 'code' => 'sn', 'arg' => 'void', 'stackfreq' => 2 },
  'div'   => { 'sub' => \&wsdiv,   'imp' => 'ts', 'code' => 'ts', 'arg' => 'void', 'stackfreq' => 2 },
  'mod'   => { 'sub' => \&wsmod,   'imp' => 'ts', 'code' => 'tt', 'arg' => 'void', 'stackfreq' => 2 },
  'stor'  => { 'sub' => \&wsstor,  'imp' => 'tt', 'code' => 's',  'arg' => 'void', 'stackfreq' => 2 },
  'retr'  => { 'sub' => \&wsretr,  'imp' => 'tt', 'code' => 't',  'arg' => 'void', 'stackfreq' => 1 },
  'mark'  => { 'sub' => \&wsmark,  'imp' => 'n',  'code' => 'ss', 'arg' => 'label', 'dontskip' => 1 },
  'call'  => { 'sub' => \&wscall,  'imp' => 'n',  'code' => 'st', 'arg' => 'label' },
  'jump'  => { 'sub' => \&wsjump,  'imp' => 'n',  'code' => 'sn', 'arg' => 'label' },
  'jzero' => { 'sub' => \&wsjzero, 'imp' => 'n',  'code' => 'ts', 'arg' => 'label', 'stackfreq' => 1 },
  'jneg'  => { 'sub' => \&wsjneg,  'imp' => 'n',  'code' => 'tt', 'arg' => 'label', 'stackfreq' => 1 },
  'ret'   => { 'sub' => \&wsret,   'imp' => 'n',  'code' => 'tn', 'arg' => 'void' },
  'end'   => { 'sub' => \&wsend,   'imp' => 'n',  'code' => 'nn', 'arg' => 'void' },
  'putc'  => { 'sub' => \&wsputc,  'imp' => 'tn', 'code' => 'ss', 'arg' => 'void', 'stackfreq' => 1 },
  'puti'  => { 'sub' => \&wsputi,  'imp' => 'tn', 'code' => 'st', 'arg' => 'void', 'stackfreq' => 1 },
  'getc'  => { 'sub' => \&wsgetc,  'imp' => 'tn', 'code' => 'ts', 'arg' => 'void', 'stackfreq' => 1 },
  'geti'  => { 'sub' => \&wsgeti,  'imp' => 'tn', 'code' => 'tt', 'arg' => 'void', 'stackfreq' => 1 },
);
sub argcode($$$)
{
  my ( $arg, $sig, $arglen ) = @_;
  $sig = '+' unless defined $sig;
  my $nosig = '';
  if ( $arg != 0 )
  {
    my @part = ();
    my $base = 1<<63;
    for ( ; $arg >= $base; $arg /= $base )
    {
       unshift @part, sprintf '%063b', $arg%$base;
    }
    $nosig = join '', ( sprintf '%b', $arg ), @part;
  }
  my $padding = defined $arglen && $arglen > length $nosig ?
                '0'x($arglen-length$nosig) : '';
  return "$sig$padding$nosig.";
}
sub convert($)
{
  if ( $codelevel == 2 )
  {
    $_[0] =~ tr/+0\-1. /ssttn/d;
  }
  elsif ( $codelevel >= 3 )
  {
    $_[0] =~ tr/+0s\-1t.n /   \t\t\t\n\n/d;
  }
}
sub compile($)
{
  my ( $lineno, $line ) = @{$_[0]};
  $line =~ /^\s*(\w+)(\s+(([-+])?(\d+)(?:\((\d+)b\))?|(\w+)))?\s*$/
    or die "invalid format at line $lineno\n";
  my $istr = $1;
  die "'$istr' is unknown at line $lineno\n"
    if ! exists $ops{$istr};
  my $ref = $ops{$istr};
  my %ret = ();
  my $argstr = '';
  my $arglen = 0;
  if ( $ref->{'arg'} eq 'void' )
  {
    die "no arguments allowed for '$istr' at line $lineno\n"
      if defined $2;
  }
  elsif ( defined $5 )
  {
    my $arg = 0+$5;
    my $sig = $4//'+';
    $argstr = argcode($arg, $sig, $6);
    $arglen = length $argstr;
    my $ilen=$arglen-2;
    $ret{'arg'} = $ref->{'arg'} eq 'label' ?
                    "$sig$arg(${ilen}b)" :
                    $sig eq '-' ? -$arg : $arg;
    $ret{'negativeargerror'} = 1
      if $ref->{'arg'} eq 'uint' && $sig eq '-';
    $labels{$ret{'arg'}}->{'count'}++
      if $ref->{'arg'} eq 'label';
  }
  else
  {
    die "invalid argument for '$istr' at line $lineno\n"
      unless $ref->{'arg'} eq 'label';
    if ( defined $7 )
    {
      $ret{'arg'} = $7;
      $ret{'relabel'} = 1;
      $labels{$ret{'arg'}}->{'relabel'} = 1;
    }
    else
    {
      $ret{'arg'} = '';
      $argstr = '.';
      $arglen = 1;
    }
    $labels{$ret{'arg'}}->{'count'}++;
  }
  if ( $codelevel > 0 )
  {
    my $code = join ' ', @$ref{qw(imp code)};
    $code .= " $argstr" if $argstr ne '';
    convert($code);
    $ret{'code'} = $code;
  }
  $bytes+=$arglen+length($ref->{'imp'})+length($ref->{'code'});
  @ret{qw(sub dontskip stackfreq)} = @$ref{qw(sub dontskip stackfreq)};
  $ret{'line'} = $lineno;
  return \%ret;
}
sub relabel()
{
  my $null_unused = !exists $labels{''};
  my ( $body, $sig, $len, $lim ) = ( 0, '+', 0, 1 );
  my ( $lcand, $code );
  foreach my $label ( sort { $labels{$b}->{'count'} <=> $labels{$a}->{'count'} || $a cmp $b }
                      grep { exists $labels{$_}->{'relabel'} } keys %labels )
  {
    my $newlabel;
    if ( $null_unused )
    {
      $newlabel = '';
      $code = '.';
      $null_unused = 0;
    }
    else
    {
      for ( my $retry=1; $retry; )
      {
        $newlabel="$sig$body(${len}b)";
        if ( !exists $labels{$newlabel} )
        {
          $retry = 0;
          $code = argcode($body,$sig,$len);
        }
        if ( $sig eq '+' )
        {
          $sig = '-';
        }
        else
        {
          $sig = '+';
          if ( ++$body >= $lim )
          {
            $body = 0;
            $len++;
            $lim*=2;
          }
        }
      }
    }
    $labels{$label}->{'relabel'} = $newlabel;
    $labels{$label}->{'code'} = $code;
    $bytes += length($code)*$labels{$label}->{'count'};
  }
  foreach my $i ( @inst )
  {
    next unless exists $i->{'relabel'};
    my $code = ' ' . $labels{$i->{'arg'}}->{'code'};
    convert($code);
    $i->{'code'} .= $code;
  }
}
sub report($)
{
  my $error = shift;
  my $ssize = @stack;
  my $hsize = @heap;
  my $msg = $error ? 'with an error' : 'normally';
  relabel();
  print <<_EOS_;
--
program ended $msg.
 instructions: $inum
 steps:        $step
 the last ip:  $ip ( line $inst[$ip-1]->{'line'} )
 src bytes:    $bytes
 stack size:   $ssize (final) / $stackhwm (high water mark)
 heap size:    $hsize
_EOS_
  print "\nlabel statistics:\n";
  if ( !%labels )
  {
    print "no label exists\n"
  }
  else
  {
    foreach my $label ( sort { $labels{$b}->{'count'} <=> $labels{$a}->{'count'} || $a cmp $b } keys %labels )
    {
      print ' ',
            ( $label eq '' ? '(null)' : $label ),
            ( exists $labels{$label}->{'relabel'} ?
                ' relabeled to ' . (
                  $labels{$label}->{'relabel'} eq '' ?
                    '(null)' : $labels{$label}->{'relabel'} ) :
                '' ),
             ': ', $labels{$label}->{'count'}, "\n";
    }
  }
  print "\nthe error is shown below:\n$error\n" if $error;
  if ( $codelevel > 0 )
  {
    print "--code--\n";
    print join $codelevel<2?"\n":"", map { $_->{'code'} } @inst;
    print "\n--end--\n";
  }
}

sub readsrc($)
{
  my $ssrc = shift;
  my $separated = defined $ssrc;
  my @lines = ();
  my $ifh = \*ARGV;
  if ( $separated )
  {
    open $ifh, '<', $ssrc
      or die "failed to open source file\n";
  }
  my $embbedopt_end = 0;
  while ( <$ifh> )
  {
    chomp;
    if ( $_ eq $ENDMARK )
    {
      die "don't use '$ENDMARK' in a separated source file\n"
        if $separated;
      last;
    }
    if ( !$embbedopt_end && /^#\+opt:\s*(\w+)(=(\w+))?/ )
    {
      if ( $1 eq 'unlimited' && !defined $2 )
      {
        $unlimited = 1;
      }
      elsif ( $1 eq 'codelevel' && defined $3 )
      {
        $codelevel = 0+$3;
      }
      elsif ( $1 eq 'limit' && defined $3 )
      {
        $slimit = 0+$3;
      }
      else
      {
        warn "invalid embbed option at line $.\n";
      }
      next;
    }
    s/\s*(#.*)?$//;
    next unless /\S/;
    push @lines, [ $., $_ ];
    $embbedopt_end = 1;
  }
  return @lines;
}

#-- main
my $usage = "Usage: $0 [-h] [-u|-l maxsteps] [-c code-level] {[merged-file] | -s srcfile [input-file]}\n";
my %opts = ();
getopts('hus:l:c:', \%opts);

die $usage if exists $opts{'h'};
$unlimited = exists $opts{'u'};
die $usage if $unlimited && exists $opts{'l'};
$slimit = $opts{'l'} // $SLIMIT_DEFAULT;
$codelevel = $opts{'c'} // $CLEVEL_DEFAULT;

my @srclines = readsrc($opts{'s'});

eval
{
  while ( $continue )
  {
    die "exceeded step limit\n"
      if !$unlimited && $step>=$slimit;
    $ip++;
    my $i;
    if ( $ip <= @inst )
    {
      $i = $inst[$ip-1];
    }
    else
    {
      if ( !@srclines )
      {
        my $sup;
        if ( defined $skip )
        {
          $sup = "mark '$skip->{'to'}'";
          $ip = $skip->{'from'};
        }
        else
        {
          $sup = 'end';
          $ip--;
        }
        die "unexpected end of source before the $sup\n"
      }
      eval
      {
        $i = compile(shift @srclines);
      };
      if ( $@ )
      {
        chomp $@;
        die "invalid instruction ( $@ )\n";
      }
      $inum++;
      push @inst, $i;
    }
    next if defined $skip && !$i->{'dontskip'};
    eval
    {
      die "negative argument is not allowed\n"
        if $i->{'negativeargerror'};
      die $i->{'stackfreq'}>1 ? "stack short\n" : "stack empty\n"
        if defined $i->{'stackfreq'} && @stack < $i->{'stackfreq'};
      &{$i->{'sub'}}(@$i{qw(arg)});
    };
    if ( $@ )
    {
      chomp $@;
      die "runtime error ( $@ at line $i->{'line'} )\n";
    }
    $step++;
  }
};
report($@);
