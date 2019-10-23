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

my $inAudioFile;
my $inLibraryPath;
my @libraryFiles;

# Functions

sub usage {
  my $usage = <<"  END_USAGE";

  This program builds C code for the Audio Hacker, made with the Teensy GUI Tool:
  https://www.pjrc.com/teensy/gui

  You must provide $prog the path to a text file with the audio data in it, and
  you must provide a path to where your teensyduino libraries are, for example: 
  /home/username/arduino-1.8.7/

    Basic Usage: $prog -audio-data [path/to/file] -libraries [path/to/libraries]

  Options:

    -audio-data [path/to/file]
      Provide the path to the audio data

    -libraries [path/to/libraries]
      Provide the base location of your libraries

    -help
      Print this help.

  Examples:

    If you copy and paste the GUI tool code into ./audioCode.txt, and your
    libraries live under ~/arduino/ ; then you can do:

      $prog -audio-data ./audioCode.txt -libraries ~/arduino/
 
  END_USAGE

  say "$usage";
  exit(0);
}

sub handle_args {
  Getopt::Long::GetOptions(
    'audio-data=s' => \$inAudioFile,
    'libraries=s' => \$inLibraryPath,
    'help' => \&usage,
  );
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
  &err("Must provide a path to the audio data!") if ! defined $inAudioFile;
  &err("Must provide a path to the teensyduino libraries!") if ! defined $inLibraryPath;
}

sub fileMatcher {
  if (/\.(h)$/) {
    push(@libraryFiles, $File::Find::name);
  }
}

sub buildIncludeFileList {
  my ($includeRef) = @_;
  my @includeShortNames = @{$includeRef};
  my @includePaths;
  
  my $lastNumIncludes = 0;
  my $currentNumIncludes = scalar @includeShortNames;

  find(\&fileMatcher, $inLibraryPath);
  

  while ($currentNumIncludes ne $lastNumIncludes) {
    say "$currentNumIncludes ne $lastNumIncludes";
    $lastNumIncludes = scalar @includeShortNames;
    for my $file (@libraryFiles) {
      my $shortName = ($file =~ /.*\/([^\/]+)$/)[0];
      if (grep {$shortName =~ /$_/i} @includeShortNames) {
        say "Found $shortName in wanted includes";
        # match
        next if grep {$file eq $_} @includePaths;
        push(@includePaths, $file) unless grep {$file eq $_} @includePaths;
        push(@includeShortNames, $shortName) unless grep {$shortName =~ /$_/i} @includeShortNames;
        for my $extraInclude (&getIncludesFromFile($file)) {
          push(@includeShortNames, $extraInclude) unless grep {$extraInclude =~ /$_/i} @includeShortNames;
        }
      }
    }
    $currentNumIncludes = scalar @includeShortNames;
  }
  #say Dumper(\@libraryFiles);
  #say Dumper(\@includePaths);
  say Dumper(\@includeShortNames);
}

sub getIncludesFromFile {
  my ($file) = @_;
  my @includes;
  open my $FH, "<", $file or die $!;
  while (my $line = <$FH>) {
    if ($line =~ /#include\s+(?:[<"]([^>"]+)[>"])/) {
      #say "$file includes $1";
      push(@includes, $1);
    }
  }
  return @includes;
}

sub main {
  &handle_args;			# deal with arguments
  &sanity;			# make sure things make sense
  my @includes = &getIncludesFromFile($inAudioFile);
  my @fullIncludeList = &buildIncludeFileList(\@includes);
  # so the idea here is to take a chunk of audio code (get that from argument parsing) and
  # understand what's in there, to write a bunch of c++ code for the teensy. then recompile it all
  # hoo boy.
}

&main;
