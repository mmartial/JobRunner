package JRHelper;
# -*- mode: Perl; tab-width: 2; indent-tabs-mode: nil -*- # For Emacs

# JobRunner's Helper Functions
#  (small adapted/extended subset of F4DE's common/lib/MMisc.pm)
#
# Author(s): Martial Michel
#
# This software was developed at the National Institute of Standards and Technology by
# employees and/or contractors of the Federal Government in the course of their official duties.
# Pursuant to Title 17 Section 105 of the United States Code this software is not subject to 
# copyright protection within the United States and is in the public domain.
#
# "JRHelper.pm" is an experimental system.
# NIST assumes no responsibility whatsoever for its use by any party.
#
# THIS SOFTWARE IS PROVIDED "AS IS."  With regard to this software, NIST MAKES NO EXPRESS
# OR IMPLIED WARRANTY AS TO ANY MATTER WHATSOEVER, INCLUDING MERCHANTABILITY,
# OR FITNESS FOR A PARTICULAR PURPOSE.


# $Id$

use strict;

use File::Temp qw(tempdir tempfile);
use Data::Dumper;
use Cwd qw(cwd abs_path);
use Time::HiRes qw(gettimeofday tv_interval usleep);

my $version     = '0.1b';

if ($version =~ m/b$/) {
  (my $cvs_version = '$Revision$') =~ s/[^\d\.]//g;
  $version = "$version (CVS: $cvs_version)";
}

my $versionid = "JRHelper.pm Version: $version";

########## No 'new' ... only functions to be useful

my $showpid = undef;

# If value is "" simply show to stdout, otherwise consider it a filename
sub set_showpid { $showpid = $_[0]; }

##
my $showpid_pre_text = "";
sub set_showpid_pre_text { $showpid_pre_text = $_[0]; }

#####
my $showpid_load_file = undef;
sub set_showpid_load_file { $showpid_load_file = $_[0]; }

##########

sub get_tmpdir {
  my $name = tempdir();
  
  return($name) 
    if (-d $name);

  return($name)
    if (&make_dir($name));

  # Directory does not exist and could not be created
  return(undef);
}

#####

# Request a temporary file (file is created)
sub get_tmpfilename {
  my ($fh, $file) = tempfile();
  return($file);
}

#####

sub slurp_file {
  my ($fname, $mode) = &iuav(\@_, '', 'text');

  return(undef) if (&is_blank($fname));

  my $out = '';
  open FILE, "<$fname"
    or return(undef);
  if ($mode eq 'bin') {
    binmode FILE;
    my $buffer = '';
    while ( read(FILE, $buffer, 65536) ) {
      $out .= $buffer;
    }
  } else {
    my @all = <FILE>;
    chomp @all;

    $out = &fast_join("\n", \@all);
  }
  close FILE;

  return($out);
}

##########

sub is_blank {
  # arg 0: variable to check
  return(1) if (! defined($_[0]));
  return(1) if (length($_[0]) == 0);

  return(1) if ($_[0] =~ m%^\s*$%s);

  return(0);
}

#####

sub any_blank {
  for (my $i = 0; $i < scalar @_; $i++) {
    my $v = $_[$i];
    return(1) if (&is_blank($v));
  }

  return(0);
}

#####

sub all_blank {
  for (my $i = 0; $i < scalar @_; $i++) {
    my $v = $_[$i];
    return(0) if (! &is_blank($v));
  }

  return(1);
}

##########

sub writeTo {
  my ($file, $addend, $printfn, $append, $txt,
      $filecomment, $stdoutcomment,
      $fileheader, $filetrailer, $makexec)
    = &iuav(\@_, '', '', 0, 0, '', '', '', '', '', 0);

  my $rv = 1;

  my $ofile = '';
  if (! &is_blank($file)) {
    if (-d $file) {
      &warn_print("Provided file ($file) is a directory, will write to STDOUT\n");
      $rv = 0;
    } else {
      $ofile = $file;
      $ofile .= $addend if (! &is_blank($addend));
    }
  }

  my $da = 0;
  if (! &is_blank($ofile)) {
    my $tofile = $ofile;
    if ($append) {
      $da = 1 if (-f $ofile);
      open FILE, ">>$ofile" or ($ofile = '');
    } else {
      open FILE, ">$ofile" or ($ofile = '');
    }
    if (&is_blank($ofile)) {
      &warn_print("Could not create \'$tofile\' (will write to STDOUT): $!\n");
      $rv = 0;
    }
  }

  if (! &is_blank($ofile)) {
    print FILE $fileheader if (! &is_blank($fileheader));
    print FILE $txt;
    print FILE $filetrailer if (! &is_blank($filetrailer));
    close FILE;
    # Note: do not print action when writing to STDOUT (even when requested)
    print((($da) ? 'Appended to file:' : 'Wrote:') . " $ofile$filecomment\n") 
      if (($ofile ne '-') && ($printfn));
    if ($ofile ne '-') {
      if ($makexec) { # Make it executable (if requested)
        chmod(0755, $ofile);
      } else { # otherwise at least try to make it world readable
        chmod(0644, $ofile);
      }
    }
    return(1); # Always return ok: we requested to write to a file and could
  }

  # Default: write to STDOUT
  print $stdoutcomment;
  print $txt;
  return($rv); # Return 0 only if we requested a file write and could not, 1 otherwise
}

##########

sub get_sorted_MemDump {
  my ($obj, $indent) = ($_[0], &iuv($_[1], 2));

  # Save the default sort key
  my $s_dso = $Data::Dumper::Sortkeys;
  # Save the default indent
  my $s_din = $Data::Dumper::Indent;
  # Save the deault Purity
  my $s_dpu = $Data::Dumper::Purity;

  # Force dumper to sort
  $Data::Dumper::Sortkeys = 1;
  # Force dumper to use requested indent level
  $Data::Dumper::Indent = $indent;
  #  Purity controls how self referential objects are written
  $Data::Dumper::Purity = 1;

  # Get the Dumper dump
  my $str = Dumper($obj);

  # Reset the keys to their previous values
  $Data::Dumper::Sortkeys = $s_dso;
  $Data::Dumper::Indent   = $s_din;
  $Data::Dumper::Purity   = $s_dpu;

  return($str);
}

#####

sub dump_memory_object {
  my ($file, $ext, $obj, $txt_fileheader, $gzip_fileheader, $printfn) =
    &iuav(\@_, '', '', undef, undef, undef, 1);

  return(0) if (! defined $obj);
  
  # The default is to write the basic text version
  my $fileheader = $txt_fileheader;
  my $str = &get_sorted_MemDump($obj);

  # But if we provide a gzip fileheader, try it
  if (defined $gzip_fileheader) {
    my $tmp = &mem_gzip($str);
    if (defined $tmp) {
      # If gzip worked, we will write this version
      $str = $tmp;
      $fileheader = $gzip_fileheader;
    }
    # Otherwise, we will write the text version
  }

  return( &writeTo($file, $ext, $printfn, 0, $str, '', '', $fileheader, '') );
}

#####

sub load_memory_object {
  my ($file, $gzhdsk) = &iuav(\@_, '', undef);

  return(undef) if (&is_blank($file));

  my $str = &slurp_file($file, 'bin');
  return(undef) if (! defined $str);

  if (defined $gzhdsk) {
    # It is possibly a gzip file => Remove the header ?
    my $tstr = &strip_header($gzhdsk, $str);
    if ($tstr ne $str) {
      # If we could it means it is a gzip file: try to un-gzip
      my $tmp = &mem_gunzip($tstr);
      return(undef) if (! defined $tmp);
      # it is un-gzipped -> work with it
      $str = $tmp;
    }
  }

  my $VAR1;
  eval $str;
  &error_quit("Internal Problem in \'JRHelper::load_memory_object()\' eval-ing code: " . join(" | ", $@))
    if $@;

  return($VAR1);
}

##########

sub mem_gzip {
  my $tozip = &iuv($_[0], '');

  return(undef) if (&is_blank($tozip));

  my $filename = &get_tmpfilename();
  open(FH, " | gzip > $filename")
    or return(undef);
  print FH $tozip;
  close FH;

  return(&slurp_file($filename, 'bin'));
}

#####

sub mem_gunzip {
  my $tounzip = &iuv($_[0], '');

  return(undef) if (&is_blank($tounzip));

  my $filename = &get_tmpfilename();
  open FILE, ">$filename"
    or return(undef);
  print FILE $tounzip;
  close FILE;

  return(&file_gunzip($filename));
}

#####

sub file_gunzip {
  my $in = &iuv($_[0], '');

  return(undef) if (&is_blank($in));
  return(undef) if (! &is_file_r($in));

  my $unzip = '';
  open(FH, "gzip -dc $in |")
    or return(undef);
  while (my $line = <FH>) { 
    $unzip .= $line;
  }
  close FH;

  return(undef) if (&is_blank($unzip));

  return($unzip);
}

##########

sub strip_header {
  my ($header, $str) = &iuav(\@_, '', '');

  return($str) if (&is_blank($header));
  return('') if (&is_blank($str));
  
  my $lh = length($header);
  
  my $sh = substr($str, 0, $lh);

  return(substr($str, $lh))
    if ($sh eq $header);
  
  return($str);
}

##########

sub _system_call_logfile {
  my ($logfile, @rest) = @_;
  
  return(-1, '', '') if (scalar @rest == 0);

  my $cmdline = '(' . join(' ', @rest) . ')'; 

  my $retcode = -1;
  my $signal = 0;
  my $stdoutfile = '';
  my $stderrfile = '';
  if ((! defined $logfile) || (&is_blank($logfile))) {
    # Get temporary filenames (created by the command line call)
    $stdoutfile = &get_tmpfilename();
    $stderrfile = &get_tmpfilename();
  } else {
    $stdoutfile = $logfile . '.stdout';
    $stderrfile = $logfile . '.stderr';
    # Create a place holder for the final logfile
    open TMP, ">$logfile"
      or return(-1, '', '');
    print TMP "Placedholder for final combined log\n\nCommandline: [$cmdline]\n\nSee \"$stdoutfile\" and \"$stderrfile\" files until the process is concluded\n";
    close TMP
  }

  my $ov = $|;
  $| = 1;

  my $pid = open (CMD, "$cmdline 1> $stdoutfile 2> $stderrfile |");
  if (defined $showpid) {
    if ($showpid eq "") {
      print "${showpid_pre_text}** Job running with PID $pid. If you need to stop it please do not use Ctrl+C, instead: \% kill $pid\n";
    } else {
      &writeTo($showpid, "", 0, 0, $pid);
    }
  }
  if (defined $showpid_load_file) {
    my $kdi = 10; # we wait a max of 2s second before failing
    while ($kdi > 0) {
      my $fpid = &slurp_file($showpid_load_file);
      if (is_blank($fpid)) {
        usleep(200000);
        $kdi--;
      } else {
        print "${showpid_pre_text}** FYI: Job running with PID $fpid. If you need to stop it please do not use Ctrl+C, instead: \% kill $fpid\n";
        $kdi = -99;
      }
    }
    print "${showpid_pre_text}** Was unable to obtain the \'saved-to-file\' PID. If you need to stop it please do not use Ctrl+C, instead try: \% kill $pid\n" if ($kdi != -99);
  }
  close CMD;
  $retcode = $? >> 8;
  $signal = $? & 127;

  $| = $ov;

  # Get the content of those temporary files
  my $stdout = &slurp_file($stdoutfile);
  my $stderr = &slurp_file($stderrfile);

  # Erase the temporary files
  unlink($stdoutfile);
  unlink($stderrfile);

  return($retcode, $stdout, $stderr, $signal, $pid);
}

#####

sub do_system_call {
  return(&_system_call_logfile(undef, @_));
}

#####

sub write_syscall_logfile {
  my $ofile = &iuv(shift @_, '');

  return(0, '', '', '', '') 
    if ( (&is_blank($ofile)) || (scalar @_ == 0) );

  my ($retcode, $stdout, $stderr, $signal, $pid) = &_system_call_logfile($ofile, @_);

  my $otxt = '[[COMMANDLINE]] ' . join(' ', @_) . "\n"
    . "[[RETURN CODE]] $retcode\n"
    . "[[SIGNAL]] $signal\n"
#    . "[[PID]] $pid\n"
    . "[[STDOUT]]\n$stdout\n\n"
    . "[[STDERR]]\n$stderr\n";

  return(0, $otxt, $stdout, $stderr, $retcode, $ofile, $signal)
    if (! &writeTo($ofile, '', 0, 0, $otxt));

  return(1, $otxt, $stdout, $stderr, $retcode, $ofile, $signal);
}

#####

sub write_syscall_smart_logfile {
  my $ofile = &iuv(shift @_, '');

  return(0, '', '', '', '') 
    if ( (&is_blank($ofile)) || (scalar @_ == 0) );

  if (-e $ofile) {
    my $date = `date "+20%y%m%d-%H%M%S"`;
    chomp($date);
    $ofile .= "-$date";
  }

  return(&write_syscall_logfile($ofile, @_));
}

##########

sub cmd_which {
  my $cmd = $_[0];
  
  my ($retcode, $stdout, $stderr) = &do_system_call('which', $cmd);
  
  return(undef) if ($retcode != 0);

  return($stdout);
}

####################

sub warn_print {
  print('[Warning] ', join(' ', @_), "\n");
}

##########

sub error_exit {
  exit(1);
}

#####

sub error_quit {
  print('[ERROR] ', join(' ', @_), "\n");
  &error_exit();
}

##########

sub ok_exit {
  exit(0);
}

#####

sub ok_quit {
  print(join(' ', @_), "\n");
  &ok_exit();
}

#####

sub sp_quit {
  my $rc = shift @_;
  print(join(' ', @_), "\n");
  exit($rc) if (defined $rc);
  ok_exit();
}

####################

sub _check_file_dir_core {
  my ($entity, $mode) = &iuav(\@_, '', '');

  return('empty mode')
    if (&is_blank($mode));

  return("empty $mode name")
    if (&is_blank($entity));
  return("$mode does not exist")
    if (! -e $entity);
  if ($mode eq 'dir') {
    return("is not a $mode")
      if (! -d $entity);
  } elsif ($mode eq 'file') {
    return("is not a $mode")
      if (! -f $entity);
  }

  return('');
}  

#####

sub _check_file_dir_XXX {
  my ($mode, $totest, $x) = &iuav(\@_, '', '', '');

  return('empty mode')
    if (&is_blank($mode));
  return('empty test')
    if (&is_blank($totest));

  my $txt = &_check_file_dir_core($x, $mode);
  return($txt) if (! &is_blank($txt));

  return('') if ($totest eq 'e');

  if ($totest eq 'r') {
    return("$mode is not readable")
      if (! -r $x);
  } elsif ($totest eq 'w') {
    return("$mode is not writable")
      if (! -w $x);
  } elsif ($totest eq 'x') {
    return("$mode is not executable")
      if (! -x $x);
  } else {
    return('unknown mode');
  }

  return('');
}

#####

sub check_file_e { return(&_check_file_dir_XXX('file', 'e', $_[0])); }
sub check_file_r { return(&_check_file_dir_XXX('file', 'r', $_[0])); }
sub check_file_w { return(&_check_file_dir_XXX('file', 'w', $_[0])); }
sub check_file_x { return(&_check_file_dir_XXX('file', 'x', $_[0])); }

sub check_dir_e { return(&_check_file_dir_XXX('dir', 'e', $_[0])); }
sub check_dir_r { return(&_check_file_dir_XXX('dir', 'r', $_[0])); }
sub check_dir_w { return(&_check_file_dir_XXX('dir', 'w', $_[0])); }
sub check_dir_x { return(&_check_file_dir_XXX('dir', 'x', $_[0])); }

sub does_file_exist { return( &is_blank( &check_file_e($_[0]) ) ); }
sub is_file_r { return( &is_blank( &check_file_r($_[0]) ) ); }
sub is_file_w { return( &is_blank( &check_file_w($_[0]) ) ); }
sub is_file_x { return( &is_blank( &check_file_x($_[0]) ) ); }

sub does_dir_exist { return( &is_blank( &check_dir_e($_[0]) ) ); }
sub is_dir_r { return( &is_blank( &check_dir_r($_[0]) ) ); }
sub is_dir_w { return( &is_blank( &check_dir_w($_[0]) ) ); }
sub is_dir_x { return( &is_blank( &check_dir_x($_[0]) ) ); }

#####

sub get_file_stat {
  my $file = &iuv($_[0], '');

  my $err = &check_file_e($file);
  return($err, undef) if (! &is_blank($err));

  my @a = stat($file);

  return("No stat obtained ($file)", undef)
    if (scalar @a == 0);

  return('', @a);
}

#####

sub _get_file_info_core {
  my ($pos, $file) = &iuav(\@_, -1, '');

  return(undef, 'Problem with function arguments')
    if ( ($pos == -1) || (&is_blank($file)) );

  my ($err, @a) = &get_file_stat($file);

  return(undef, $err)
    if (! &is_blank($err));

  return($a[$pos], '');
}

#####

sub get_file_uid   {return(&_get_file_info_core(4, @_));} 
sub get_file_gid   {return(&_get_file_info_core(5, @_));} 
sub get_file_size  {return(&_get_file_info_core(7, @_));} 
sub get_file_atime {return(&_get_file_info_core(8, @_));} 
sub get_file_mtime {return(&_get_file_info_core(9, @_));} 
sub get_file_ctime {return(&_get_file_info_core(10, @_));} 

#####  

# Note: will only keep "ok" files in the output list
sub sort_files {
  my $criteria = &iuv($_[0], '');

  my $func = undef;
  if ($criteria eq 'size') {
    $func = \&get_file_size;
  } elsif ($criteria eq 'atime') {
    $func = \&get_file_atime;
  } elsif ($criteria eq 'mtime') {
    $func = \&get_file_mtime;
  } elsif ($criteria eq 'ctime') {
    $func = \&get_file_ctime;
  } else {
    return('Unknown criteria', undef);
  }

  my %tmp = ();
  my @errs = ();
  for (my $i = 1; $i < scalar @_; $i++) {
    my $file = $_[$i];
    my ($v, $err) = &$func($file);
    if (! &is_blank($err)) {
      push @errs, $err;
      next;
    }
    if (! defined $v) {
      push @errs, "Undefined value for \'$file\''s \'$criteria\'";
      next;
    }
    $tmp{$file} = $v;
  }

  my @out = sort { $tmp{$a} <=> $tmp{$b} } keys %tmp;

  my $errmsg = join('. ', @errs);

  return($errmsg, @out);
}

#####

# Note: will return undef if any file in the list is not "ok"
sub _XXXest_core {
  my $mode = &iuv(shift @_, '');

  my @out = ();

  return(@out) if (&is_blank($mode));

  my ($err, @or) = &sort_files($mode, @_);

  return(@out)
    if (scalar @or != scalar @_);

  return(@or);
}

#####

sub newest {
  my @or = &_XXXest_core('mtime', @_);

  return(undef) if (scalar @or == 0);

  return($or[-1]);
}

#####

sub oldest {
  my @or = &_XXXest_core('mtime', @_);

  return(undef) if (scalar @or == 0);

  return($or[0]);
}

####################

# Will create directories up to requested depth
sub make_dir {
  my ($dest, $perm) = &iuav(\@_, '', 0755);

  return(0) if (&is_blank($dest));

  return(1) if (-d $dest);

  $perm = 0755 if (&is_blank($perm)); # default permissions

  my $t = '';
  my @todo = split(m%/%, $dest);
  for (my $i = 0; $i < scalar @todo; $i++) {
    my $d = $todo[$i];
    $t .= "$d/";
    next if (-d $t);

    mkdir($t, $perm);
    last if (! -d $t);
  }

  return(0) if (! -d $dest);

  return(1);
}

#####

sub make_wdir {
  my $ok = &make_dir(@_);
  return($ok) if (! $ok);
  return(&is_dir_w($_[0]));
}

##########

sub list_dirs_files {
  my $dir = &iuv($_[0], '');

  return('Empty dir name', undef, undef, undef)
    if (&is_blank($dir));

  opendir DIR, "$dir"
    or return("Problem opening directory ($dir) : $!", undef, undef, undef);
  my @fl = grep(! m%^\.\.?%, readdir(DIR));
  close DIR;

  my @d = ();
  my @f = ();
  my @u = ();
  for (my $i = 0; $i < scalar @fl; $i++) {
    my $entry = $fl[$i];
    my $ff = "$dir/$entry";
    if (-d $ff) {
      push @d, $entry;
      next;
    }
    if (-f $ff) {
      push @f, $entry;
      next;
    }
    push @u, $entry;
  }

  return('', \@d, \@f, \@u);
}

#####

sub get_dirs_list {
  my $dir = &iuv($_[0], '');

  my @out = ();

  return(@out) if (&is_blank($dir));

  my ($err, $rd, $rf, $ru) = &list_dirs_files($dir);

  return(@out) if (! &is_blank($err));

  return(@{$rd});
}

#####

sub get_files_list {
  my $dir = &iuv($_[0], '');

  my @out = ();

  return(@out) if (&is_blank($dir));

  my ($err, $rd, $rf, $ru) = &list_dirs_files($dir);

  return(@out) if (! &is_blank($err));

  return(@{$rf});
}

##########

sub get_pwd { return(cwd()); }

#####

sub get_file_full_path {
  my ($rp, $from) = &iuav(\@_, '', &get_pwd());

  return($rp) if (&is_blank($rp));

  my $f = $rp;
  $f = "$from/$rp" if ($rp !~ m%^\/%);

  my $o = abs_path($f);

  $o = $f
    if (&is_blank($o)); # The request PATH does not exist, fake it

  return($o);
}

##########

sub iuav { # Initialize Undefined Array of Values
  my ($ra, @rest) = @_;

  my @out = ();
  for (my $i = 0; $i < scalar @rest; $i++) {
    push @out, &iuv($$ra[$i], $rest[$i]);
  }

  return(@out);
}

#####

sub iuv { # Initialize Undefined Values
  # arg 0: value to check
  # arg 1: replacement if undefined (can be 'undef')
  return(defined $_[0] ? $_[0] : $_[1]);
}

##########

sub fast_join {
  # arg 0: join separator
  # arg 1: reference to array of entries to be joined

  return('') if (scalar @{$_[1]} == 0);

  my $txt = ${$_[1]}[0];
  for (my $i = 1; $i < scalar @{$_[1]}; $i++) {
    $txt .= $_[0] . ${$_[1]}[$i];
  }

  return($txt);
}

####################

sub get_currenttime { return([gettimeofday()]); }
sub get_scalar_currenttime { return(scalar gettimeofday()); }

#####

sub get_elapsedtime { return(tv_interval($_[0])); }

#####

sub epoch2str {
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime( $_[0] );
  return(sprintf("%04d%02d%02d-%02d%02d%02d", $year + 1900, 1 + $mon, $mday, $hour, $min, $sec));
}

##########

1;
