package ExtUtils::Liblist;
use vars qw($VERSION);
# Broken out of MakeMaker from version 4.11

$VERSION = substr q$Revision: 1.2201 $, 10;

use Config;
use Cwd 'cwd';
use File::Basename;

sub ext {
  if   ($^O eq 'VMS') { return &_vms_ext;      }
  else                { return &_unix_os2_ext; }
}

sub _unix_os2_ext {
    my($self,$potential_libs, $Verbose) = @_;
    if ($^O =~ 'os2' and $Config{libs}) { 
	# Dynamic libraries are not transitive, so we may need including
	# the libraries linked against perl.dll again.

	$potential_libs .= " " if $potential_libs;
	$potential_libs .= $Config{libs};
    }
    return ("", "", "", "") unless $potential_libs;
    print STDOUT "Potential libraries are '$potential_libs':\n" if $Verbose;

    my($so)   = $Config{'so'};
    my($libs) = $Config{'libs'};
    my $Config_libext = $Config{lib_ext} || ".a";


    # compute $extralibs, $bsloadlibs and $ldloadlibs from
    # $potential_libs
    # this is a rewrite of Andy Dougherty's extliblist in perl
    # its home is in <distribution>/ext/util

    my(@searchpath); # from "-L/path" entries in $potential_libs
    my(@libpath) = split " ", $Config{'libpth'};
    my(@ldloadlibs, @bsloadlibs, @extralibs, @ld_run_path, %ld_run_path_seen);
    my($fullname, $thislib, $thispth, @fullname);
    my($pwd) = cwd(); # from Cwd.pm
    my($found) = 0;

    foreach $thislib (split ' ', $potential_libs){

	# Handle possible linker path arguments.
	if ($thislib =~ s/^(-[LR])//){	# save path flag type
	    my($ptype) = $1;
	    unless (-d $thislib){
		print STDOUT "$ptype$thislib ignored, directory does not exist\n"
			if $Verbose;
		next;
	    }
	    unless ($self->file_name_is_absolute($thislib)) {
	      print STDOUT "Warning: $ptype$thislib changed to $ptype$pwd/$thislib\n";
	      $thislib = $self->catdir($pwd,$thislib);
	    }
	    push(@searchpath, $thislib);
	    push(@extralibs,  "$ptype$thislib");
	    push(@ldloadlibs, "$ptype$thislib");
	    next;
	}

	# Handle possible library arguments.
	unless ($thislib =~ s/^-l//){
	  print STDOUT "Unrecognized argument in LIBS ignored: '$thislib'\n";
	  next;
	}

	my($found_lib)=0;
	foreach $thispth (@searchpath, @libpath){

		# Try to find the full name of the library.  We need this to
		# determine whether it's a dynamically-loadable library or not.
		# This tends to be subject to various os-specific quirks.
		# For gcc-2.6.2 on linux (March 1995), DLD can not load
		# .sa libraries, with the exception of libm.sa, so we
		# deliberately skip them.
	    if (@fullname =
		    $self->lsdir($thispth,"^\Qlib$thislib.$so.\E[0-9]+")){
		# Take care that libfoo.so.10 wins against libfoo.so.9.
		# Compare two libraries to find the most recent version
		# number.  E.g.  if you have libfoo.so.9.0.7 and
		# libfoo.so.10.1, first convert all digits into two
		# decimal places.  Then we'll add ".00" to the shorter
		# strings so that we're comparing strings of equal length
		# Thus we'll compare libfoo.so.09.07.00 with
		# libfoo.so.10.01.00.  Some libraries might have letters
		# in the version.  We don't know what they mean, but will
		# try to skip them gracefully -- we'll set any letter to
		# '0'.  Finally, sort in reverse so we can take the
		# first element.

		#TODO: iterate through the directory instead of sorting

		$fullname = "$thispth/" .
		(sort { my($ma) = $a;
			my($mb) = $b;
			$ma =~ tr/A-Za-z/0/s;
			$ma =~ s/\b(\d)\b/0$1/g;
			$mb =~ tr/A-Za-z/0/s;
			$mb =~ s/\b(\d)\b/0$1/g;
			while (length($ma) < length($mb)) { $ma .= ".00"; }
			while (length($mb) < length($ma)) { $mb .= ".00"; }
			# Comparison deliberately backwards
			$mb cmp $ma;} @fullname)[0];
	    } elsif (-f ($fullname="$thispth/lib$thislib.$so")
		 && (($Config{'dlsrc'} ne "dl_dld.xs") || ($thislib eq "m"))){
	    } elsif (-f ($fullname="$thispth/lib${thislib}_s$Config_libext")
		 && ($thislib .= "_s") ){ # we must explicitly use _s version
	    } elsif (-f ($fullname="$thispth/lib$thislib$Config_libext")){
	    } elsif (-f ($fullname="$thispth/$thislib$Config_libext")){
	    } elsif (-f ($fullname="$thispth/Slib$thislib$Config_libext")){
	    } elsif ($^O eq 'dgux'
		 && -l ($fullname="$thispth/lib$thislib$Config_libext")
		 && readlink($fullname) =~ /^elink:/) {
		 # Some of DG's libraries look like misconnected symbolic
		 # links, but development tools can follow them.  (They
		 # look like this:
		 #
		 #    libm.a -> elink:${SDE_PATH:-/usr}/sde/\
		 #    ${TARGET_BINARY_INTERFACE:-m88kdgux}/usr/lib/libm.a
		 #
		 # , the compilation tools expand the environment variables.)
	    } else {
		print STDOUT "$thislib not found in $thispth\n" if $Verbose;
		next;
	    }
	    print STDOUT "'-l$thislib' found at $fullname\n" if $Verbose;
	    my($fullnamedir) = dirname($fullname);
	    push @ld_run_path, $fullnamedir unless $ld_run_path_seen{$fullnamedir}++;
	    $found++;
	    $found_lib++;

	    # Now update library lists

	    # what do we know about this library...
	    my $is_dyna = ($fullname !~ /\Q$Config_libext\E$/);
	    my $in_perl = ($libs =~ /\B-l\Q$ {thislib}\E\b/s);

	    # Do not add it into the list if it is already linked in
	    # with the main perl executable.
	    # We have to special-case the NeXT, because math and ndbm 
	    # are both in libsys_s
	    unless ($in_perl || 
		($Config{'osname'} eq 'next' &&
		    ($thislib eq 'm' || $thislib eq 'ndbm')) ){
		push(@extralibs, "-l$thislib");
	    }

	    # We might be able to load this archive file dynamically
	    if ( ($Config{'dlsrc'} =~ /dl_next/ && $Config{'osvers'} lt '4_0')
	    ||   ($Config{'dlsrc'} =~ /dl_dld/) )
	    {
		# We push -l$thislib instead of $fullname because
		# it avoids hardwiring a fixed path into the .bs file.
		# Mkbootstrap will automatically add dl_findfile() to
		# the .bs file if it sees a name in the -l format.
		# USE THIS, when dl_findfile() is fixed: 
		# push(@bsloadlibs, "-l$thislib");
		# OLD USE WAS while checking results against old_extliblist
		push(@bsloadlibs, "$fullname");
	    } else {
		if ($is_dyna){
                    # For SunOS4, do not add in this shared library if
                    # it is already linked in the main perl executable
		    push(@ldloadlibs, "-l$thislib")
			unless ($in_perl and $^O eq 'sunos');
		} else {
		    push(@ldloadlibs, "-l$thislib");
		}
	    }
	    last;	# found one here so don't bother looking further
	}
	print STDOUT "Note (probably harmless): "
		     ."No library found for -l$thislib\n"
	    unless $found_lib>0;
    }
    return ('','','','') unless $found;
    ("@extralibs", "@bsloadlibs", "@ldloadlibs",join(":",@ld_run_path));
}


sub _vms_ext {
  my($self, $potential_libs,$verbose) = @_;
  return ('', '', '', '') unless $potential_libs;

  my(@dirs,@libs,$dir,$lib,%sh,%olb,%obj);
  my $cwd = cwd();
  my($so,$lib_ext,$obj_ext) = @Config{'so','lib_ext','obj_ext'};
  # List of common Unix library names and there VMS equivalents
  # (VMS equivalent of '' indicates that the library is automatially
  # searched by the linker, and should be skipped here.)
  my %libmap = ( 'm' => '', 'f77' => '', 'F77' => '', 'V77' => '', 'c' => '',
                 'malloc' => '', 'crypt' => '', 'resolv' => '', 'c_s' => '',
                 'socket' => '', 'X11' => 'DECW$XLIBSHR',
                 'Xt' => 'DECW$XTSHR', 'Xm' => 'DECW$XMLIBSHR',
                 'Xmu' => 'DECW$XMULIBSHR');
  if ($Config{'vms_cc_type'} ne 'decc') { $libmap{'curses'} = 'VAXCCURSE'; }

  print STDOUT "Potential libraries are '$potential_libs'\n" if $verbose;

  # First, sort out directories and library names in the input
  foreach $lib (split ' ',$potential_libs) {
    push(@dirs,$1),   next if $lib =~ /^-L(.*)/;
    push(@dirs,$lib), next if $lib =~ /[:>\]]$/;
    push(@dirs,$lib), next if -d $lib;
    push(@libs,$1),   next if $lib =~ /^-l(.*)/;
    push(@libs,$lib);
  }
  push(@dirs,split(' ',$Config{'libpth'}));

  # Now make sure we've got VMS-syntax absolute directory specs
  # (We don't, however, check whether someone's hidden a relative
  # path in a logical name.)
  foreach $dir (@dirs) {
    unless (-d $dir) {
      print STDOUT "Skipping nonexistent Directory $dir\n" if $verbose > 1;
      $dir = '';
      next;
    }
    print STDOUT "Resolving directory $dir\n" if $verbose;
    if ($self->file_name_is_absolute($dir)) { $dir = $self->fixpath($dir,1); }
    else                                    { $dir = $self->catdir($cwd,$dir); }
  }
  @dirs = grep { length($_) } @dirs;
  unshift(@dirs,''); # Check each $lib without additions first

  LIB: foreach $lib (@libs) {
    if (exists $libmap{$lib}) {
      next unless length $libmap{$lib};
      $lib = $libmap{$lib};
    }

    my(@variants,$variant,$name,$test,$cand);
    my($ctype) = '';

    # If we don't have a file type, consider it a possibly abbreviated name and
    # check for common variants.  We try these first to grab libraries before
    # a like-named executable image (e.g. -lperl resolves to perlshr.exe
    # before perl.exe).
    if ($lib !~ /\.[^:>\]]*$/) {
      push(@variants,"${lib}shr","${lib}rtl","${lib}lib");
      push(@variants,"lib$lib") if $lib !~ /[:>\]]/;
    }
    push(@variants,$lib);
    print STDOUT "Looking for $lib\n" if $verbose;
    foreach $variant (@variants) {
      foreach $dir (@dirs) {
        my($type);

        $name = "$dir$variant";
        print "\tChecking $name\n" if $verbose > 2;
        if (-f ($test = VMS::Filespec::rmsexpand($name))) {
          # It's got its own suffix, so we'll have to figure out the type
          if    ($test =~ /(?:$so|exe)$/i)      { $type = 'sh'; }
          elsif ($test =~ /(?:$lib_ext|olb)$/i) { $type = 'olb'; }
          elsif ($test =~ /(?:$obj_ext|obj)$/i) {
            print STDOUT "Note (probably harmless): "
			 ."Plain object file $test found in library list\n";
            $type = 'obj';
          }
          else {
            print STDOUT "Note (probably harmless): "
			 ."Unknown library type for $test; assuming shared\n";
            $type = 'sh';
          }
        }
        elsif (-f ($test = VMS::Filespec::rmsexpand($name,$so))      or
               -f ($test = VMS::Filespec::rmsexpand($name,'.exe')))     {
          $type = 'sh';
          $name = $test unless $test =~ /exe;?\d*$/i;
        }
        elsif (not length($ctype) and  # If we've got a lib already, don't bother
               ( -f ($test = VMS::Filespec::rmsexpand($name,$lib_ext)) or
                 -f ($test = VMS::Filespec::rmsexpand($name,'.olb'))))  {
          $type = 'olb';
          $name = $test unless $test =~ /olb;?\d*$/i;
        }
        elsif (not length($ctype) and  # If we've got a lib already, don't bother
               ( -f ($test = VMS::Filespec::rmsexpand($name,$obj_ext)) or
                 -f ($test = VMS::Filespec::rmsexpand($name,'.obj'))))  {
          print STDOUT "Note (probably harmless): "
		       ."Plain object file $test found in library list\n";
          $type = 'obj';
          $name = $test unless $test =~ /obj;?\d*$/i;
        }
        if (defined $type) {
          $ctype = $type; $cand = $name;
          last if $ctype eq 'sh';
        }
      }
      if ($ctype) { 
        eval '$' . $ctype . "{'$cand'}++";
        die "Error recording library: $@" if $@;
        print STDOUT "\tFound as $cand (really $ctest), type $ctype\n" if $verbose > 1;
        next LIB;
      }
    }
    print STDOUT "Note (probably harmless): "
		 ."No library found for $lib\n";
  }

  @libs = sort keys %obj;
  # This has to precede any other CRTLs, so just make it first
  if ($olb{VAXCCURSE}) {
    push(@libs,"$olb{VAXCCURSE}/Library");
    delete $olb{VAXCCURSE};
  }
  push(@libs, map { "$_/Library" } sort keys %olb);
  push(@libs, map { "$_/Share"   } sort keys %sh);
  $lib = join(' ',@libs);
  print "Result: $lib\n" if $verbose;
  wantarray ? ($lib, '', $lib, '') : $lib;
}

1;

__END__

=head1 NAME

ExtUtils::Liblist - determine libraries to use and how to use them

=head1 SYNOPSIS

C<require ExtUtils::Liblist;>

C<ExtUtils::Liblist::ext($potential_libs, $Verbose);>

=head1 DESCRIPTION

This utility takes a list of libraries in the form C<-llib1 -llib2
-llib3> and prints out lines suitable for inclusion in an extension
Makefile.  Extra library paths may be included with the form
C<-L/another/path> this will affect the searches for all subsequent
libraries.

It returns an array of four scalar values: EXTRALIBS, BSLOADLIBS,
LDLOADLIBS, and LD_RUN_PATH.

Dependent libraries can be linked in one of three ways:

=over 2

=item * For static extensions

by the ld command when the perl binary is linked with the extension
library. See EXTRALIBS below.

=item * For dynamic extensions

by the ld command when the shared object is built/linked. See
LDLOADLIBS below.

=item * For dynamic extensions

by the DynaLoader when the shared object is loaded. See BSLOADLIBS
below.

=back

=head2 EXTRALIBS

List of libraries that need to be linked with when linking a perl
binary which includes this extension Only those libraries that
actually exist are included.  These are written to a file and used
when linking perl.

=head2 LDLOADLIBS and LD_RUN_PATH

List of those libraries which can or must be linked into the shared
library when created using ld. These may be static or dynamic
libraries.  LD_RUN_PATH is a colon separated list of the directories
in LDLOADLIBS. It is passed as an environment variable to the process
that links the shared library.

=head2 BSLOADLIBS

List of those libraries that are needed but can be linked in
dynamically at run time on this platform.  SunOS/Solaris does not need
this because ld records the information (from LDLOADLIBS) into the
object file.  This list is used to create a .bs (bootstrap) file.

=head1 PORTABILITY

This module deals with a lot of system dependencies and has quite a
few architecture specific B<if>s in the code.

=head2 VMS implementation

The version of ext() which is executed under VMS differs from the
Unix-OS/2 version in several respects:

=over 2

=item *

Input library and path specifications are accepted with or without the
C<-l> and C<-L> prefices used by Unix linkers.  If neither prefix is
present, a token is considered a directory to search if it is in fact
a directory, and a library to search for otherwise.  Authors who wish
their extensions to be portable to Unix or OS/2 should use the Unix
prefixes, since the Unix-OS/2 version of ext() requires them.

=item *

Wherever possible, shareable images are preferred to object libraries,
and object libraries to plain object files.  In accordance with VMS
naming conventions, ext() looks for files named I<lib>shr and I<lib>rtl;
it also looks for I<lib>lib and libI<lib> to accomodate Unix conventions
used in some ported software.

=item *

For each library that is found, an appropriate directive for a linker options
file is generated.  The return values are space-separated strings of
these directives, rather than elements used on the linker command line.

=item *

LDLOADLIBS and EXTRALIBS are always identical under VMS, and BSLOADLIBS
and LD_RIN_PATH are always empty.

=back

In addition, an attempt is made to recognize several common Unix library
names, and filter them out or convert them to their VMS equivalents, as
appropriate.

In general, the VMS version of ext() should properly handle input from
extensions originally designed for a Unix or VMS environment.  If you
encounter problems, or discover cases where the search could be improved,
please let us know.

=head1 SEE ALSO

L<ExtUtils::MakeMaker>

=cut

