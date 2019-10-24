#!/usr/bin/env perl
# by William Hofferbert
#

use 5.010;				# say
use strict;				# good form
use warnings;				# know when stuff is wrong
use Data::Dumper;			# debug
$Data::Dumper::Sortkeys = 1;		# woooo!
use File::Basename;			# know where the script lives
use File::Find;
use Getopt::Long;			# handle arguments

# Default Variables

my $prog = basename($0);

my $inAudioFile;
my $inAudioFileData;
my $inLibraryPath;
my @libraryFiles;

my $cppTypesRegex = "void|bool|short|long|int|uint8_t|float";

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
  print STDERR "Gathering all related libraries ...";
  my ($includeRef) = @_;
  my @includeShortNames = @{$includeRef};
  my @includePaths;
  
  my $lastNumIncludes = 0;
  my $currentNumIncludes = scalar @includeShortNames;

  find(\&fileMatcher, $inLibraryPath);
  

  while ($currentNumIncludes ne $lastNumIncludes) {
    {
      $| = 1;
      print STDERR ".";
      #say "$currentNumIncludes ne $lastNumIncludes";
    }
    $lastNumIncludes = scalar @includeShortNames;
    for my $file (@libraryFiles) {
      my $shortName = ($file =~ /.*\/([^\/]+)$/)[0];
      if (grep {$shortName =~ /\b$_\b/i} @includeShortNames) {
        #say "Found $shortName in wanted includes";
        # match
        next if grep {$file eq $_} @includePaths;
        push(@includePaths, $file) unless grep {$file eq $_} @includePaths;
        push(@includeShortNames, $shortName) unless grep {$shortName =~ /\b$_\b/i} @includeShortNames;
        for my $extraInclude (&getIncludesFromFile($file)) {
          push(@includeShortNames, $extraInclude) unless grep {$extraInclude =~ /\b$_\b/i} @includeShortNames;
        }
      }
    }
    $currentNumIncludes = scalar @includeShortNames;
  }
  {
    $| = 1;
    print STDERR "\n";
  }
  return (@includePaths);
}

sub getIncludesFromFile {
  my ($file) = @_;
  my @includes;
  open my $FH, "<", $file or die $!;
  while (my $line = <$FH>) {
    if ($line =~ /^\s*#include\s+(?:[<"]([^>"]+)[>"])/) {
      #say "$file includes $1";
      push(@includes, $1);
    }
  }
  close $FH;
  return @includes;
}

sub readAudioFileData {
  open my $FH, "<", $inAudioFile or die $!;
  while (my $line = <$FH>) {
    $inAudioFileData .= $line;
  }
  close $FH;
}

sub getClassObjects {
  my %HoA;
  for my $line (split(/\n/, $inAudioFileData)) {
    if ($line =~ /^(\w+)\s+([\w_]+);/) {
      push(@{$HoA{$1}}, $2);
    }
  }
  return (%HoA);
}

sub getAudioClasses {
  my @types;
  for my $line (split(/\n/, $inAudioFileData)) {
    if ($line =~ /^(\w+)\s+\w+;/) {
      push @types, $1;
    }
  }
  return (@types);
}

sub getObjectsOfClasses {
  my %H;
  for my $line (split(/\n/, $inAudioFileData)) {
    if ($line =~ /^(\w+)\s+([\w_]+);/) {
      $H{$2} = $1;
    }
  }
  return (%H);
}

sub findClassStuffInLibs {
  my %stuff;
  my ($reqRef, $fileRef) = @_;
  my @required = @{$reqRef};
  my @files = @{$fileRef};

  my $regex = join"|", @required;

  for my $file (@files) {
    my $fileData;
    open my $FH, "<", $file or die $!;
    while (my $line = <$FH>) {
      $fileData .= $line;
    }
    close $FH;
    while ($fileData =~ /(class\s+\b($regex)\b.*?\n\}\;)/sg) {
      # matched file on class
      my $classMatch = $1;
      my $matchedReq = $2;
      my $scrubData;
      if ($classMatch =~ /\n\s*protected:/s) {
        $scrubData = ($classMatch =~ /^(.*)(?=\nprotected:)/s)[0];
      } elsif ($classMatch =~ /\n\s*private:/s) {
        $scrubData = ($classMatch =~ /^(.*)(?=\n\s*private:)/s)[0];
      } else {
        $scrubData = $classMatch;
      }
      if (! defined $scrubData) {
        say "WTF is up with $file ??";
        next;
      }
      # fuck.... we will have to look for voids and all sorts of shit here as well
      my $foundFuncs = 0;
      while ($scrubData =~ /((?:(?:\w+ )?(?:$cppTypesRegex))\s+\w+\s*\((?!\s*void)[^\)]+\))/sg) {
        push(@{$stuff{$matchedReq}{paramFuncs}}, $1);
        $foundFuncs = 1;
      }
      while ($scrubData =~ /(?<!virtual )(void\s+\w+\s*\((?:\s*void|)\))/sg) {
        push(@{$stuff{$matchedReq}{voidFuncs}}, $1);
        $foundFuncs = 1;
      }
      if ($foundFuncs == 1) {
        $stuff{$matchedReq}{file} = $file;
      }
    }
  }
  return (%stuff);
}


#
# TODO this might need to accept another variable of the type of plugin
# and then reference this against known things to adjust stuff... ?
#
sub cppCallDeconstructor {
  my ($effectName, $effectType, $cpp) = @_;
  #my ($cpp) = @_;
  my %hash;

  my $cppTypeNameRegex = '(\S+(?: \S+)?)\s+(\S+)$';

  if ($cpp =~ /([^\(]+)\(([^\)]*)\)/) {
    my $typeAndObject = $1;
    my $parenEnclosure = $2;
    #say "start: $start ; parens: $parens";
    # set up typeAndObject
    if ($typeAndObject =~ /$cppTypeNameRegex/) {
      my $callType = $1;
      my $callName = $2;

      # mmmm
      if ($callName =~ /begin/) {
        # skip begin ?
        return;
      }

      $hash{effectName} = $effectName;
      $hash{effectType} = $effectType;
      $hash{callType} = $callType;
      $hash{callName} = $callName;
    }
    if ($parenEnclosure =~ /\S+/) {
      for my $param (split(/\,\s*/, $parenEnclosure)) {
        # skip pointers because we can't ignorantly change them
        next if $param =~ /\*/;
        if ($param =~ /$cppTypeNameRegex/) {
          my $paramType = $1;
          my $paramName = $2;
          my @paramTuple = ($1, $2);
          push(@{$hash{params}}, \@paramTuple);
        }
      }
    } else { 
      # NOTE this is DIFFERENT. it's ON/OFF. footswitches and the like
      $hash{bool} = 1;
    }
  }
  return %hash;
}

sub buildCppStructFromGarbage {
  my ($objClassRef, $dataRef) = @_;
  my %objectsOfClasses = %{$objClassRef};
  my %data = %{$dataRef};
  #say Dumper(\%data); exit;
  my @struct;
  for my $specificEffect (sort keys %objectsOfClasses) {
    my @effectSettings;
    my $effectType = $objectsOfClasses{$specificEffect};
    # 
    #  TODO fuck. function name overloading means that we have 
    #  to account for multiple functions named the same, but wityh
    #  different parameter lists. That'll be a name adjustment for the menu
    #  but we have to keep it pointed at the right thing. .....
    # 
    #  but since we call the deconstructor once on eevery call
    #  we can get the return from it, and parse the dumb out later
    # 
    # 
    if (exists $data{$effectType}{paramFuncs}) {
      # param stuff
      for my $modifier (@{$data{$effectType}{paramFuncs}}) {
        my %layout = &cppCallDeconstructor($specificEffect, $effectType, $modifier);
        push(@effectSettings, \%layout)
      }
    }
    if (exists $data{$effectType}{voidFuncs}) {
      # void stuff
      for my $modifier (@{$data{$effectType}{voidFuncs}}) {
        next if $modifier =~ /\bbegin\b/;
        my %void = &cppCallDeconstructor($specificEffect, $effectType, $modifier);
        unless (keys %void) {
          say "major malfunction: $specificEffect $effectType $modifier";
          next;
        }
        #say "VOOOOOOOOOOOOID";
        #say Dumper(\%void);
        push(@effectSettings, \%void);
      }
    }
    if (scalar @effectSettings == 0) {
      say "BUTTHOLES: $specificEffect";
      say Dumper($objectsOfClasses{$specificEffect});
    } else {
      ## stuff
      push(@struct, \@effectSettings);
    }
  }
  return @struct;
}


sub main {
  &handle_args;			# deal with arguments
  &sanity;			# make sure things make sense
  &readAudioFileData;
  my @audioDataReqs = &getAudioClasses;
  my %classObjects = &getClassObjects;
  my %objectsOfClasses = &getObjectsOfClasses;
  my @includes = &getIncludesFromFile($inAudioFile);
  my @fullIncludeList = &buildIncludeFileList(\@includes);
  my %data = &findClassStuffInLibs(\@audioDataReqs, \@fullIncludeList);
  #say Dumper(\%data);

  ## mmmm ... sort by first array element of hash objects
  my @menuStruct = &buildCppStructFromGarbage(\%objectsOfClasses, \%data);
  #say Dumper(\@menuStruct);
  #say Dumper(\$menuStruct[0]);
  for my $bit (@menuStruct) {
    my @arr = @{$bit};
    # TODO this seems broken
    next unless @arr;
    my $effectName = $arr[0]{effectName};
    say $effectName;
    say Dumper(\$bit);
  }
  # so the idea here is to take a chunk of audio code (get that from argument parsing) and
  # understand what's in there, to write a bunch of c++ code for the teensy. then recompile it all
  # hoo boy.
}

&main;
