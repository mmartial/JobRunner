#!/usr/bin/env perl
# -*- mode: Perl; tab-width: 2; indent-tabs-mode: nil -*- # For Emacs

# Job Runner Caller
#
# Author(s): Martial Michel
#
# This software was developed at the National Institute of Standards and Technology by
# employees and/or contractors of the Federal Government in the course of their official duties.
# Pursuant to Title 17 Section 105 of the United States Code this software is not subject to 
# copyright protection within the United States and is in the public domain.
#
# "JobRunner Caller" is an experimental system.
# NIST assumes no responsibility whatsoever for its use by any party.
#
# THIS SOFTWARE IS PROVIDED "AS IS."  With regard to this software, NIST MAKES NO EXPRESS
# OR IMPLIED WARRANTY AS TO ANY MATTER WHATSOEVER, INCLUDING MERCHANTABILITY,
# OR FITNESS FOR A PARTICULAR PURPOSE.

use strict;

my $sd = "";
BEGIN {
  use Cwd 'abs_path';
  use File::Basename 'dirname';
  $sd = dirname(abs_path($0));
}
use lib ($sd);

# Note: Designed for UNIX style environments (ie use cygwin under Windows).

##########
# Version

# $Id$
my $version     = "0.1b";

if ($version =~ m/b$/) {
  (my $cvs_version = '$Revision$') =~ s/[^\d\.]//g;
  $version = "$version (CVS: $cvs_version)";
}

my $versionid = "JobRunner Caller Version: $version";

##########
# Check we have every module (perl wise)

sub eo2pe {
  my $oe = join(" ", @_);
  return( ($oe !~ m%^Can\'t\s+locate%) ? "\n----- Original Error:\n $oe\n-----" : "");
}

## Then try to load everything
my $have_everything = 1;
my $partofthistool = "It should have been part of this tools' files. ";
my $warn_msg = "";
sub _warn_add { $warn_msg .= "[Warning] " . join(" ", @_) ."\n"; }

# Part of this tool
foreach my $pn ("JRHelper") {
  unless (eval "use $pn; 1") {
    my $pe = &eo2pe($@);
    &_warn_add("\"$pn\" is not available in your Perl installation. ", $partofthistool, $pe);
    $have_everything = 0;
  }
}

# usualy part of the Perl Core
foreach my $pn ("Getopt::Long") {
  unless (eval "use $pn; 1") {
    &_warn_add("\"$pn\" is not available on your Perl installation. ", "Please look it up on CPAN [http://search.cpan.org/]\n");
    $have_everything = 0;
  }
}

# Something missing ? Abort
if (! $have_everything) {
  print "\n$warn_msg\nERROR: Some Perl Modules are missing, aborting\n";
  exit(1);
}

# Use the long mode of Getopt
Getopt::Long::Configure(qw(auto_abbrev no_ignore_case));

########################################
# Options processing

my $dsleepv = 60;

my $usage = &set_usage();
JRHelper::ok_quit("\n$usage\n") if (scalar @ARGV == 0);

# Av  : ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz  #
# Used:          J       RS           e  h       pqrs  vw     #

my $toolb = "JobRunner";
my $tool = JRHelper::cmd_which($toolb);
$tool = JRHelper::cmd_which(dirname(abs_path($0)) . "/$toolb.pl") if (! defined $tool);
$tool = JRHelper::cmd_which(dirname(abs_path($0)) . "/$toolb") if (! defined $tool);
my @watchdir = ();
my $sleepv = $dsleepv;
my $retryall = 0;
my $verb = 1;
my $random = undef;
my $sibj = 0;
my @dironce = ();
my $passreport = 0;

my %opt = ();
GetOptions
  (
   \%opt,
   'help',
   'version',
   'JobRunner=s' => \$tool,
   'watchdir=s' => \@watchdir,
   'sleep=i'    => \$sleepv,
   'retryall'   => \$retryall,
   'quiet'      => sub {$verb = 0},
   'RandomOrder:-99' => \$random,
   'SleepInBetweenJobs=i' => \$sibj,
   'dironce=s'      => \@dironce,
   'endSetReport:i' => \$passreport,
  ) or JRHelper::error_quit("Wrong option(s) on the command line, aborting\n\n$usage\n");
JRHelper::ok_quit("\n$usage\n\nAutoDection of \'$toolb\' found: $tool\n") if ($opt{'help'});
JRHelper::ok_quit("$versionid\n") if ($opt{'version'});

JRHelper::error_quit("Problem with \'$toolb\' tool ($tool): not found")
  if ((! defined $tool) || (! JRHelper::does_file_exists($tool)));
my $err = JRHelper::check_file_x($tool);
JRHelper::error_quit("Problem with \'$toolb\' tool ($tool): $err")
  if (! JRHelper::is_blank($err));

JRHelper::error_quit("\SleepInBetweenJobs\' values must be positive ($sibj)")
  if ($sibj < 0);

my $randi = 0;
my $rands = 0;
my @randa = ();
if (defined $random) {
  $random = time() if ($random == -99);
  srand($random);
  # just to be safe (if anything were to use "rand()" it would change the order)
  # -> get 10K entries in advance
  set_randa(10000);
}

my $kdi = scalar @watchdir; # keep doing it

my %alldone = ();
my %todo = ();
my %done = ();
my $todoc = 0;
my $donec = 0;
my %notdone = ();

my %allsetsdone = ();
my $set = 1;

do {
  my @tobedone = ();
  %alldone = () if ($retryall);

  foreach my $file (@ARGV) {
    next if (exists $alldone{$file});
    push @tobedone, $file;
  }

  while (my $dir = shift @dironce) {
    my $err = JRHelper::check_dir_r($dir);
    JRHelper::error_quit("Problem with directory ($dir): $err")
      if (! JRHelper::is_blank($err));
    my @in = JRHelper::get_files_list($dir);
    foreach my $file (@in) {
      my $ff = "$dir/$file";
      next if (exists $alldone{$ff});
      push @tobedone, $ff;
    }
  }

  foreach my $dir (@watchdir) {
    my $err = JRHelper::check_dir_r($dir);
    JRHelper::error_quit("Problem with directory ($dir): $err")
      if (! JRHelper::is_blank($err));
    my @in = JRHelper::get_files_list($dir);
    foreach my $file (@in) {
      my $ff = "$dir/$file";
      next if (exists $alldone{$ff});
      push @tobedone, $ff;
    }
  }

  if (defined $random) {
    @tobedone = sort _rand @tobedone;
  }

  foreach my $jrc (@tobedone) {
    next if (exists $alldone{$jrc});

    $todo{$jrc}++;

    my ($ok, $txt, $ds, $msg) = &doit($jrc);
    print "$txt\n" if (! JRHelper::is_blank($txt));
    
    if ($ok) {
      $done{$jrc}++;
      delete $notdone{$jrc};
    }

    $notdone{$jrc} = $msg if (! JRHelper::is_blank($msg));

    if (($ds) && ($sibj)) {
      print " (waiting $sibj seconds)\n";
      sleep($sibj);
    }
  }
  
  $todoc = scalar(keys %todo);
  $donec = scalar(keys %done);
  print "\n\n%%%%%%%%%% Set " . $set++ . " run results: $donec / $todoc %%%%%%%%%%\n";
  if ($passreport) {
    print "%%% Set Report:\n";
    my %tmpr = ();
    foreach my $v (sort keys %notdone) { push @{$tmpr{$notdone{$v}}}, $v; }
    foreach my $v (sort keys %tmpr) {
      print " ** \"$v\" found in:\n     - " . join("\n     - ", @{$tmpr{$v}}) . "\n";
    }
  }
  
  if ($kdi) {
    print " (waiting $sleepv seconds)\n";
    sleep($sleepv);
  }


} while ($kdi);

JRHelper::ok_quit("Done ($donec / $todoc)\n");

########################################

sub __cleanmsg {
  # check every JobRunner's 'ok_quit' for string and adapt message

  # no need to report, all was well
  return("") if ($_[0] =~ m%Previously\ssuccesfully\scompleted$%);
  return("") if ($_[0] =~ m%Previously\ssuccesfully\scompleted\,\sand.+$%);
  return("") if ($_[0] =~ m%Job\ssuccesfully\scompleted$%);

  # just in case user need a status on jobs
  return($1) if ($_[0] =~ m%(Skip\srequested)$%);
  return($1) if ($_[0] =~ m%(Previous\sbad\srun\spresent\,\sskipping)$%);
  return(($passreport > 1) ? $1 : "") if ($_[0] =~ m%(Job\salready\sin\sprogress\,\sSkipping)$%);
  return($1) if ($_[0] =~ m%(\\\'RunIfTrue\\\'\scheck\sdid\snot\ssucceed.+)$%);
  
  #
  return("UNKNOWN: " . $_[0]);
}

##

sub doit {
  my ($jrc) = @_;

  # whatever happens here after, we will not redo this entry (at least this set)
  $alldone{$jrc}++;
  $allsetsdone{$jrc}++; # if > 1 it means we have already done it in the past
  # and therefore do not print "skip" info anymore

  my $header = "\n\n[**] Job Runner Config: \'$jrc\'";

  my $err = JRHelper::check_file_r($jrc);
  return(0, 
         ($allsetsdone{$jrc} < 2) 
         ? "$header\n  !! Skipping -- Problem with file ($jrc): $err"
         : "", 0, "File Issue: $err") if (! JRHelper::is_blank($err));
  
  $err = &check_header($jrc);
  return(0,
         ($allsetsdone{$jrc} < 2)
         ? "$header\n  -- Skipping -- $err"
         : "", 0, $err) if (! JRHelper::is_blank($err));

  my $jb_cmd = "$tool -u $jrc";

  my $tjb_cmd = "$jb_cmd -O";
  my ($rc, $so, $se) = JRHelper::do_system_call($tjb_cmd);

  return(1,
         ($allsetsdone{$jrc} < 2)
         ? ("$header\n  @@ Can be skipped" . ($verb ? "\n(stdout)$so" : ""))
         : "", 0, &__cleanmsg($so)) if ($rc == 0);
  
  return(1, "$header\n  ?? Possible Problem" . 
         ($verb ? "\n(stdout)$so\n(stderr)$se" : ""), 0, "Possible Problem") if ($rc == 1);

  ## To be run ? run it !
  # and now really print the header
  print "$header\n";

  my ($rc, $so, $se) = JRHelper::do_system_call($jb_cmd);
  
  return(1, "  ++ Job completed" . ($verb ? "\n(stdout)$so" : ""), 1, "")
    if ($rc == 0);
  
  return(0, "  ** ERROR Run" . ($verb ? "\n(stdout)$so\n(stderr)$se" : ""), 1, "ERROR RUN");
}

#####

sub check_header {
  my $jrc = $_[0];
  
  open FILE, "<$jrc"
    or return("Problem opening file ($jrc) : $!");
  
  my $header = <FILE>;
  chomp $header;
  close FILE;
  
#  print "[$header]\n";
  return("File header is not the expected text")
    if ($header ne "# Job Runner Configuration file");

  return("");
}

##########

sub set_randa {
  for (my $i = 0; $i < $_[0]; $i++) {
    push @randa, rand();
  }
  $rands = scalar @randa;
}

#####

sub get_rand {
  JRHelper::error_quit("Can not get pre computed rand() value from array (no content)")
    if ($rands == 0);
  my $mul = (defined $_[0]) ? $_[0] : 1;
  my $v = $mul * $randa[$randi];
  $randi++;
  $randi = 0 if ($randi >= $rands);
  return($v);
}

#####

sub _num { $a <=> $b; }

##

sub _rand { &get_rand(100) <=> &get_rand(100); }

########################################

sub set_usage {  
  my $tmp=<<EOF
$versionid

$0 [--help | --version] [--JobRunner executable] [--quiet] [--endSetReport [level]] [--SleepInBetweenJobs seconds] [--watchdir dir [--watchdir dir [...]] [--dironce dir [--dironce dir [...]] [--sleep seconds] [--retryall] [--RandomOrder [seed]]] [JobRunner_configfile [JobRunner_configfile [...]]]

Will execute JobRunner jobs 

Where:
  --help       This help message
  --version    Version information
  --JobRunner  Location of executable tool (if not in PATH, will also look for it tool dir)
  --quiet      Do not print stdout/stderr data from system calls
  --endSetReport  At the end of a set, print a report of job status (bypassing succesfully completed jobs) (default \'level\' is to not print \'already in progress\' jobs, use a \'level\' of 2 to add those)
  --SleepInBetweenJobs  Specify the number of seconds to sleep in between two consecutive jobs (example: when a job check the system load before running using JobRunner\'s \'--RunIfTrue\', this allow the load to drop some) (default is not to sleep)
  --watchdir   Directory to look for configuration files [*]
  --dironce    Directory to look for configuration files only once
  --sleep      Specify the sleep time in between sets
  --retryall   When running a different set, retry all previously completed entries (especially useful when when a JobRunner configuration uses \'--badErase\' or \'--RunIfTrue\')
  --RandomOrder  Run jobs in random order instead of the order they are provided (can help with multiple lock dir access over NFS if the data is not propagated from server yet) (note: if providing a random seed --which must be over 0-- use different values for multiple JobRunner_Caller, or simply do not provide any and the current \'time\' value will be used)

*: in this mode, the program will complete a full run then on the files found in this directory, then sleep $dsleepv seconds before re-reading the directory content and see if any new configuration file is present, before running it. The program will never stop, it is left to the user to stop the program.


EOF
;

  return($tmp);
}
