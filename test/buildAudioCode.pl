#!/usr/bin/env perl
# by William Hofferbert
#

use 5.010;				# say
use strict;				# good form
use warnings;				# know when stuff is wrong
use Data::Dumper;			# debug
use File::Basename;			# know where the script lives
use File::Find;
use Getopt::Long;			# handle arguments

# Default Variables

my $prog = basename($0);

# Functions

sub usage {
  my $usage = <<"  END_USAGE";

  This program does ____

    Basic Usage: $prog 

  Options:

    -help
      Print this help.

  Examples:

    $prog 
 
  END_USAGE

  say "$usage";
  exit(0);
}

sub check_required_args {		# handle leftover @ARGV stuff here if need be
  # &err("no file provided!") unless -f $ARGV[0];
}

sub handle_args {
  if ( Getopt::Long::GetOptions(
    #'string=s' => \$var,
    #'int=i' => \$var,
    #'float=f' => \$var,
    #'verbose' => \$var,
    'help' => \&usage,
     ) )   {
    &check_required_args;
  }
}


sub err {
  my $msg=shift;
  say "$msg";
  exit 2;
}

sub warn {
  my $msg=shift;
  say "$msg";
}

sub sanity {
  # &warn("not sane") unless @things_are_okay;
}

sub main {
  &handle_args;			# deal with arguments
  &sanity;			# make sure things make sense
  # so the idea here is to take a chunk of audio code (get that from argument parsing) and
  # understand what's in there, to write a bunch of c++ code for the teensy. then recompile it all
  # hoo boy.
}

&main;
