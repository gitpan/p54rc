package DB;

# Debugger for Perl 5.00x; perl5db.pl patch level:

$VERSION = 1.00;
$header = "perl5db.pl version $VERSION";

# Enhanced by ilya@math.ohio-state.edu (Ilya Zakharevich)
# Latest version available: ftp://ftp.math.ohio-state.edu/pub/users/ilya/perl

# modified Perl debugger, to be run from Emacs in perldb-mode
# Ray Lischner (uunet!mntgfx!lisch) as of 5 Nov 1990
# Johan Vromans -- upgrade to 4.0 pl 10
# Ilya Zakharevich -- patches after 5.001 (and some before ;-)

#
# This file is automatically included if you do perl -d.
# It's probably not useful to include this yourself.
#
# Perl supplies the values for %sub.  It effectively inserts
# a &DB'DB(); in front of every place that can have a
# breakpoint. Instead of a subroutine call it calls &DB::sub with
# $DB::sub being the called subroutine. It also inserts a BEGIN
# {require 'perl5db.pl'} before the first line.
#
# After each `require'd file is compiled, but before it is executed, a
# call to DB::postponed($main::{'_<'.$filename}) is emulated. Here the
# $filename is the expanded name of the `require'd file (as found as
# value of %INC).
#
# Additional services from Perl interpreter:
#
# if caller() is called from the package DB, it provides some
# additional data.
#
# The array @{$main::{'_<'.$filename} is the line-by-line contents of
# $filename.
#
# The hash %{'_<'.$filename} contains breakpoints and action (it is
# keyed by line number), and individual entries are settable (as
# opposed to the whole hash). Only true/false is important to the
# interpreter, though the values used by perl5db.pl have the form
# "$break_condition\0$action". Values are magical in numeric context.
#
# The scalar ${'_<'.$filename} contains "_<$filename".
#
# Note that no subroutine call is possible until &DB::sub is defined
# (for subroutines defined outside of the package DB). In fact the same is
# true if $deep is not defined.
#
# $Log:	perldb.pl,v $

#
# At start reads $rcfile that may set important options.  This file
# may define a subroutine &afterinit that will be executed after the
# debugger is initialized.
#
# After $rcfile is read reads environment variable PERLDB_OPTS and parses
# it as a rest of `O ...' line in debugger prompt.
#
# The options that can be specified only at startup:
# [To set in $rcfile, call &parse_options("optionName=new_value").]
#
# TTY  - the TTY to use for debugging i/o.
#
# noTTY - if set, goes in NonStop mode.  On interrupt if TTY is not set
# uses the value of noTTY or "/tmp/perldbtty$$" to find TTY using
# Term::Rendezvous.  Current variant is to have the name of TTY in this
# file.
#
# ReadLine - If false, dummy ReadLine is used, so you can debug
# ReadLine applications.
#
# NonStop - if true, no i/o is performed until interrupt.
#
# LineInfo - file or pipe to print line number info to.  If it is a
# pipe, a short "emacs like" message is used.
#
# Example $rcfile: (delete leading hashes!)
#
# &parse_options("NonStop=1 LineInfo=db.out");
# sub afterinit { $trace = 1; }
#
# The script will run without human intervention, putting trace
# information into db.out.  (If you interrupt it, you would better
# reset LineInfo to something "interactive"!)
#
##################################################################
# Changelog:

# A lot of things changed after 0.94. First of all, core now informs
# debugger about entry into XSUBs, overloaded operators, tied operations,
# BEGIN and END. Handy with `O f=2'.

# This can make debugger a little bit too verbose, please be patient
# and report your problems promptly.

# Now the option frame has 3 values: 0,1,2.

# Note that if DESTROY returns a reference to the object (or object),
# the deletion of data may be postponed until the next function call,
# due to the need to examine the return value.

# Changes: 0.95: `v' command shows versions.
# Changes: 0.96: `v' command shows version of readline.
#	primitive completion works (dynamic variables, subs for `b' and `l',
#		options). Can `p %var'
#	Better help (`h <' now works). New commands <<, >>, {, {{.
#	{dump|print}_trace() coded (to be able to do it from <<cmd).
#	`c sub' documented.
#	At last enough magic combined to stop after the end of debuggee.
#	!! should work now (thanks to Emacs bracket matching an extra
#	`]' in a regexp is caught).
#	`L', `D' and `A' span files now (as documented).
#	Breakpoints in `require'd code are possible (used in `R').
#	Some additional words on internal work of debugger.
#	`b load filename' implemented.
#	`b postpone subr' implemented.
#	now only `q' exits debugger (overwriteable on $inhibit_exit).
#	When restarting debugger breakpoints/actions persist.
#     Buglet: When restarting debugger only one breakpoint/action per 
#		autoloaded function persists.
# Changes: 0.97: NonStop will not stop in at_exit().
#	Option AutoTrace implemented.
#	Trace printed differently if frames are printed too.
#	new `inhibitExit' option.
#	printing of a very long statement interruptible.
# Changes: 0.98: New command `m' for printing possible methods
#	'l -' is a synonim for `-'.
#	Cosmetic bugs in printing stack trace.
#	`frame' & 8 to print "expanded args" in stack trace.
#	Can list/break in imported subs.
#	new `maxTraceLen' option.
#	frame & 4 and frame & 8 granted.
#	new command `m'
#	nonstoppable lines do not have `:' near the line number.
#	`b compile subname' implemented.
#	Will not use $` any more.
#	`-' behaves sane now.
# Changes: 0.99: Completion for `f', `m'.
#	`m' will remove duplicate names instead of duplicate functions.
#	`b load' strips trailing whitespace.
#	completion ignores leading `|'; takes into account current package
#	when completing a subroutine name (same for `l').

####################################################################

# Needed for the statement after exec():

BEGIN { $ini_warn = $^W; $^W = 0 } # Switch compilation warnings off until another BEGIN.
local($^W) = 0;			# Switch run-time warnings off during init.
warn (			# Do not ;-)
      $dumpvar::hashDepth,     
      $dumpvar::arrayDepth,    
      $dumpvar::dumpDBFiles,   
      $dumpvar::dumpPackages,  
      $dumpvar::quoteHighBit,  
      $dumpvar::printUndef,    
      $dumpvar::globPrint,     
      $dumpvar::usageOnly,
      @ARGS,
      $Carp::CarpLevel,
      $panic,
      $second_time,
     ) if 0;

# Command-line + PERLLIB:
@ini_INC = @INC;

# $prevwarn = $prevdie = $prevbus = $prevsegv = ''; # Does not help?!

$trace = $signal = $single = 0;	# Uninitialized warning suppression
                                # (local $^W cannot help - other packages!).
$inhibit_exit = $option{PrintRet} = 1;

@options     = qw(hashDepth arrayDepth DumpDBFiles DumpPackages 
		  compactDump veryCompact quote HighBit undefPrint
		  globPrint PrintRet UsageOnly frame AutoTrace
		  TTY noTTY ReadLine NonStop LineInfo maxTraceLen
		  recallCommand ShellBang pager tkRunning ornaments
		  signalLevel warnLevel dieLevel inhibit_exit);

%optionVars    = (
		 hashDepth	=> \$dumpvar::hashDepth,
		 arrayDepth	=> \$dumpvar::arrayDepth,
		 DumpDBFiles	=> \$dumpvar::dumpDBFiles,
		 DumpPackages	=> \$dumpvar::dumpPackages,
		 HighBit	=> \$dumpvar::quoteHighBit,
		 undefPrint	=> \$dumpvar::printUndef,
		 globPrint	=> \$dumpvar::globPrint,
		 UsageOnly	=> \$dumpvar::usageOnly,     
		 frame          => \$frame,
		 AutoTrace      => \$trace,
		 inhibit_exit   => \$inhibit_exit,
		 maxTraceLen	=> \$maxtrace,
);

%optionAction  = (
		  compactDump	=> \&dumpvar::compactDump,
		  veryCompact	=> \&dumpvar::veryCompact,
		  quote		=> \&dumpvar::quote,
		  TTY		=> \&TTY,
		  noTTY		=> \&noTTY,
		  ReadLine	=> \&ReadLine,
		  NonStop	=> \&NonStop,
		  LineInfo	=> \&LineInfo,
		  recallCommand	=> \&recallCommand,
		  ShellBang	=> \&shellBang,
		  pager		=> \&pager,
		  signalLevel	=> \&signalLevel,
		  warnLevel	=> \&warnLevel,
		  dieLevel	=> \&dieLevel,
		  tkRunning	=> \&tkRunning,
		  ornaments	=> \&ornaments,
		 );

%optionRequire = (
		  compactDump	=> 'dumpvar.pl',
		  veryCompact	=> 'dumpvar.pl',
		  quote		=> 'dumpvar.pl',
		 );

# These guys may be defined in $ENV{PERL5DB} :
$rl = 1 unless defined $rl;
$warnLevel = 1 unless defined $warnLevel;
$dieLevel = 1 unless defined $dieLevel;
$signalLevel = 1 unless defined $signalLevel;
$pre = [] unless defined $pre;
$post = [] unless defined $post;
$pretype = [] unless defined $pretype;
warnLevel($warnLevel);
dieLevel($dieLevel);
signalLevel($signalLevel);
&pager(defined($ENV{PAGER}) ? $ENV{PAGER} : "|more") unless defined $pager;
&recallCommand("!") unless defined $prc;
&shellBang("!") unless defined $psh;
$maxtrace = 400 unless defined $maxtrace;

if (-e "/dev/tty") {
  $rcfile=".perldb";
} else {
  $rcfile="perldb.ini";
}

if (-f $rcfile) {
    do "./$rcfile";
} elsif (defined $ENV{LOGDIR} and -f "$ENV{LOGDIR}/$rcfile") {
    do "$ENV{LOGDIR}/$rcfile";
} elsif (defined $ENV{HOME} and -f "$ENV{HOME}/$rcfile") {
    do "$ENV{HOME}/$rcfile";
}

if (defined $ENV{PERLDB_OPTS}) {
  parse_options($ENV{PERLDB_OPTS});
}

if (exists $ENV{PERLDB_RESTART}) {
  delete $ENV{PERLDB_RESTART};
  # $restart = 1;
  @hist = get_list('PERLDB_HIST');
  %break_on_load = get_list("PERLDB_ON_LOAD");
  %postponed = get_list("PERLDB_POSTPONE");
  my @had_breakpoints= get_list("PERLDB_VISITED");
  for (0 .. $#had_breakpoints) {
    my %pf = get_list("PERLDB_FILE_$_");
    $postponed_file{$had_breakpoints[$_]} = \%pf if %pf;
  }
  my %opt = get_list("PERLDB_OPT");
  my ($opt,$val);
  while (($opt,$val) = each %opt) {
    $val =~ s/[\\\']/\\$1/g;
    parse_options("$opt'$val'");
  }
  @INC = get_list("PERLDB_INC");
  @ini_INC = @INC;
  $pretype = [get_list("PERLDB_PRETYPE")];
  $pre = [get_list("PERLDB_PRE")];
  $post = [get_list("PERLDB_POST")];
  @typeahead = get_list("PERLDB_TYPEAHEAD", @typeahead);
}

if ($notty) {
  $runnonstop = 1;
} else {
  # Is Perl being run from Emacs?
  $emacs = ((defined $main::ARGV[0]) and ($main::ARGV[0] eq '-emacs'));
  $rl = 0, shift(@main::ARGV) if $emacs;

  #require Term::ReadLine;

  if (-e "/dev/tty") {
    $console = "/dev/tty";
  } elsif (-e "con" or $^O eq 'MSWin32') {
    $console = "con";
  } else {
    $console = "sys\$command";
  }

  # Around a bug:
  if (defined $ENV{OS2_SHELL} and ($emacs or $ENV{WINDOWID})) { # In OS/2
    $console = undef;
  }

  $console = $tty if defined $tty;

  if (defined $console) {
    open(IN,"+<$console") || open(IN,"<$console") || open(IN,"<&STDIN");
    open(OUT,"+>$console") || open(OUT,">$console") || open(OUT,">&STDERR")
      || open(OUT,">&STDOUT");	# so we don't dongle stdout
  } else {
    open(IN,"<&STDIN");
    open(OUT,">&STDERR") || open(OUT,">&STDOUT"); # so we don't dongle stdout
    $console = 'STDIN/OUT';
  }
  # so open("|more") can read from STDOUT and so we don't dingle stdin
  $IN = \*IN;

  $OUT = \*OUT;
  select($OUT);
  $| = 1;			# for DB::OUT
  select(STDOUT);

  $LINEINFO = $OUT unless defined $LINEINFO;
  $lineinfo = $console unless defined $lineinfo;

  $| = 1;			# for real STDOUT

  $header =~ s/.Header: ([^,]+),v(\s+\S+\s+\S+).*$/$1$2/;
  unless ($runnonstop) {
    print $OUT "\nLoading DB routines from $header\n";
    print $OUT ("Emacs support ",
		$emacs ? "enabled" : "available",
		".\n");
    print $OUT "\nEnter h or `h h' for help.\n\n";
  }
}

@ARGS = @ARGV;
for (@args) {
    s/\'/\\\'/g;
    s/(.*)/'$1'/ unless /^-?[\d.]+$/;
}

if (defined &afterinit) {	# May be defined in $rcfile
  &afterinit();
}

$I_m_init = 1;

############################################################ Subroutines

sub DB {
    # _After_ the perl program is compiled, $single is set to 1:
    if ($single and not $second_time++) {
      if ($runnonstop) {	# Disable until signal
	for ($i=0; $i <= $#stack; ) {
	    $stack[$i++] &= ~1;
	}
	$single = 0;
	# return;			# Would not print trace!
      }
    }
    $runnonstop = 0 if $single or $signal; # Disable it if interactive.
    &save;
    ($package, $filename, $line) = caller;
    $filename_ini = $filename;
    $usercontext = '($@, $!, $,, $/, $\, $^W) = @saved;' .
      "package $package;";	# this won't let them modify, alas
    local(*dbline) = $main::{'_<' . $filename};
    $max = $#dbline;
    if (($stop,$action) = split(/\0/,$dbline{$line})) {
	if ($stop eq '1') {
	    $signal |= 1;
	} elsif ($stop) {
	    $evalarg = "\$DB::signal |= do {$stop;}"; &eval;
	    $dbline{$line} =~ s/;9($|\0)/$1/;
	}
    }
    my $was_signal = $signal;
    $signal = 0;
    if ($single || $trace || $was_signal) {
	$term || &setterm;
	if ($emacs) {
	    $position = "\032\032$filename:$line:0\n";
	    print $LINEINFO $position;
	} else {
	    $sub =~ s/\'/::/;
	    $prefix = $sub =~ /::/ ? "" : "${'package'}::";
	    $prefix .= "$sub($filename:";
	    $after = ($dbline[$line] =~ /\n$/ ? '' : "\n");
	    if (length($prefix) > 30) {
	        $position = "$prefix$line):\n$line:\t$dbline[$line]$after";
		$prefix = "";
		$infix = ":\t";
	    } else {
		$infix = "):\t";
		$position = "$prefix$line$infix$dbline[$line]$after";
	    }
	    if ($frame) {
		print $LINEINFO ' ' x $#stack, "$line:\t$dbline[$line]$after";
	    } else {
		print $LINEINFO $position;
	    }
	    for ($i = $line + 1; $i <= $max && $dbline[$i] == 0; ++$i) { #{ vi
		last if $dbline[$i] =~ /^\s*[\;\}\#\n]/;
		last if $signal;
		$after = ($dbline[$i] =~ /\n$/ ? '' : "\n");
		$incr_pos = "$prefix$i$infix$dbline[$i]$after";
		$position .= $incr_pos;
		if ($frame) {
		    print $LINEINFO ' ' x $#stack, "$i:\t$dbline[$i]$after";
		} else {
		    print $LINEINFO $incr_pos;
		}
	    }
	}
    }
    $evalarg = $action, &eval if $action;
    if ($single || $was_signal) {
	local $level = $level + 1;
	foreach $evalarg (@$pre) {
	  &eval;
	}
	print $OUT $#stack . " levels deep in subroutine calls!\n"
	  if $single & 4;
	$start = $line;
	$incr = -1;		# for backward motion.
	@typeahead = @$pretype, @typeahead;
      CMD:
	while (($term || &setterm),
	       defined ($cmd=&readline("  DB" . ('<' x $level) .
				       ($#hist+1) . ('>' x $level) .
				       " "))) {
		$single = 0;
		$signal = 0;
		$cmd =~ s/\\$/\n/ && do {
		    $cmd .= &readline("  cont: ");
		    redo CMD;
		};
		$cmd =~ /^$/ && ($cmd = $laststep);
		push(@hist,$cmd) if length($cmd) > 1;
	      PIPE: {
		    ($i) = split(/\s+/,$cmd);
		    eval "\$cmd =~ $alias{$i}", print $OUT $@ if $alias{$i};
		    $cmd =~ /^q$/ && ($exiting = 1) && exit 0;
		    $cmd =~ /^h$/ && do {
			print $OUT $help;
			next CMD; };
		    $cmd =~ /^h\s+h$/ && do {
			print $OUT $summary;
			next CMD; };
		    $cmd =~ /^h\s+(\S)$/ && do {
			my $asked = "\Q$1";
			if ($help =~ /^$asked/m) {
			  while ($help =~ /^($asked([\s\S]*?)\n)(\Z|[^\s$asked])/mg) {
			    print $OUT $1;
			  }
			} else {
			    print $OUT "`$asked' is not a debugger command.\n";
			}
			next CMD; };
		    $cmd =~ /^t$/ && do {
			$trace = !$trace;
			print $OUT "Trace = ".($trace?"on":"off")."\n";
			next CMD; };
		    $cmd =~ /^S(\s+(!)?(.+))?$/ && do {
			$Srev = defined $2; $Spatt = $3; $Snocheck = ! defined $1;
			foreach $subname (sort(keys %sub)) {
			    if ($Snocheck or $Srev^($subname =~ /$Spatt/)) {
				print $OUT $subname,"\n";
			    }
			}
			next CMD; };
		    $cmd =~ /^v$/ && do {
			list_versions(); next CMD};
		    $cmd =~ s/^X\b/V $package/;
		    $cmd =~ /^V$/ && do {
			$cmd = "V $package"; };
		    $cmd =~ /^V\b\s*(\S+)\s*(.*)/ && do {
			local ($savout) = select($OUT);
			$packname = $1;
			@vars = split(' ',$2);
			do 'dumpvar.pl' unless defined &main::dumpvar;
			if (defined &main::dumpvar) {
			    local $frame = 0;
			    local $doret = -2;
			    &main::dumpvar($packname,@vars);
			} else {
			    print $OUT "dumpvar.pl not available.\n";
			}
			select ($savout);
			next CMD; };
		    $cmd =~ s/^x\b/ / && do { # So that will be evaled
			$onetimeDump = 'dump'; };
		    $cmd =~ s/^m\s+([\w:]+)\s*$/ / && do {
			methods($1); next CMD};
		    $cmd =~ s/^m\b/ / && do { # So this will be evaled
			$onetimeDump = 'methods'; };
		    $cmd =~ /^f\b\s*(.*)/ && do {
			$file = $1;
			$file =~ s/\s+$//;
			if (!$file) {
			    print $OUT "The old f command is now the r command.\n";
			    print $OUT "The new f command switches filenames.\n";
			    next CMD;
			}
			if (!defined $main::{'_<' . $file}) {
			    if (($try) = grep(m#^_<.*$file#, keys %main::)) {{
					      $try = substr($try,2);
					      print $OUT "Choosing $try matching `$file':\n";
					      $file = $try;
					  }}
			}
			if (!defined $main::{'_<' . $file}) {
			    print $OUT "No file matching `$file' is loaded.\n";
			    next CMD;
			} elsif ($file ne $filename) {
			    *dbline = $main::{'_<' . $file};
			    $max = $#dbline;
			    $filename = $file;
			    $start = 1;
			    $cmd = "l";
			  } else {
			    print $OUT "Already in $file.\n";
			    next CMD;
			  }
		      };
		    $cmd =~ s/^l\s+-\s*$/-/;
		    $cmd =~ /^l\b\s*([\':A-Za-z_][\':\w]*)/ && do {
			$subname = $1;
			$subname =~ s/\'/::/;
			$subname = $package."::".$subname 
			  unless $subname =~ /::/;
			$subname = "main".$subname if substr($subname,0,2) eq "::";
			@pieces = split(/:/,find_sub($subname));
			$subrange = pop @pieces;
			$file = join(':', @pieces);
			if ($file ne $filename) {
			    *dbline = $main::{'_<' . $file};
			    $max = $#dbline;
			    $filename = $file;
			}
			if ($subrange) {
			    if (eval($subrange) < -$window) {
				$subrange =~ s/-.*/+/;
			    }
			    $cmd = "l $subrange";
			} else {
			    print $OUT "Subroutine $subname not found.\n";
			    next CMD;
			} };
		    $cmd =~ /^\.$/ && do {
			$incr = -1;		# for backward motion.
			$start = $line;
			$filename = $filename_ini;
			*dbline = $main::{'_<' . $filename};
			$max = $#dbline;
			print $LINEINFO $position;
			next CMD };
		    $cmd =~ /^w\b\s*(\d*)$/ && do {
			$incr = $window - 1;
			$start = $1 if $1;
			$start -= $preview;
			#print $OUT 'l ' . $start . '-' . ($start + $incr);
			$cmd = 'l ' . $start . '-' . ($start + $incr); };
		    $cmd =~ /^-$/ && do {
			$start -= $incr + $window + 1;
			$start = 1 if $start <= 0;
			$incr = $window - 1;
			$cmd = 'l ' . ($start) . '+'; };
		    $cmd =~ /^l$/ && do {
			$incr = $window - 1;
			$cmd = 'l ' . $start . '-' . ($start + $incr); };
		    $cmd =~ /^l\b\s*(\d*)\+(\d*)$/ && do {
			$start = $1 if $1;
			$incr = $2;
			$incr = $window - 1 unless $incr;
			$cmd = 'l ' . $start . '-' . ($start + $incr); };
		    $cmd =~ /^l\b\s*((-?[\d\$\.]+)([-,]([\d\$\.]+))?)?/ && do {
			$end = (!defined $2) ? $max : ($4 ? $4 : $2);
			$end = $max if $end > $max;
			$i = $2;
			$i = $line if $i eq '.';
			$i = 1 if $i < 1;
			$incr = $end - $i;
			if ($emacs) {
			    print $OUT "\032\032$filename:$i:0\n";
			    $i = $end;
			} else {
			    for (; $i <= $end; $i++) {
			        ($stop,$action) = split(/\0/, $dbline{$i});
			        $arrow = ($i==$line 
					  and $filename eq $filename_ini) 
				  ?  '==>' 
				    : ($dbline[$i]+0 ? ':' : ' ') ;
				$arrow .= 'b' if $stop;
				$arrow .= 'a' if $action;
				print $OUT "$i$arrow\t", $dbline[$i];
				last if $signal;
			    }
			}
			$start = $i; # remember in case they want more
			$start = $max if $start > $max;
			next CMD; };
		    $cmd =~ /^D$/ && do {
		      print $OUT "Deleting all breakpoints...\n";
		      my $file;
		      for $file (keys %had_breakpoints) {
			local *dbline = $main::{'_<' . $file};
			my $max = $#dbline;
			my $was;
			
			for ($i = 1; $i <= $max ; $i++) {
			    if (defined $dbline{$i}) {
				$dbline{$i} =~ s/^[^\0]+//;
				if ($dbline{$i} =~ s/^\0?$//) {
				    delete $dbline{$i};
				}
			    }
			}
		      }
		      undef %postponed;
		      undef %postponed_file;
		      undef %break_on_load;
		      undef %had_breakpoints;
		      next CMD; };
		    $cmd =~ /^L$/ && do {
		      my $file;
		      for $file (keys %had_breakpoints) {
			local *dbline = $main::{'_<' . $file};
			my $max = $#dbline;
			my $was;
			
			for ($i = 1; $i <= $max; $i++) {
			    if (defined $dbline{$i}) {
			        print "$file:\n" unless $was++;
				print $OUT " $i:\t", $dbline[$i];
				($stop,$action) = split(/\0/, $dbline{$i});
				print $OUT "   break if (", $stop, ")\n"
				  if $stop;
				print $OUT "   action:  ", $action, "\n"
				  if $action;
				last if $signal;
			    }
			}
		      }
		      if (%postponed) {
			print $OUT "Postponed breakpoints in subroutines:\n";
			my $subname;
			for $subname (keys %postponed) {
			  print $OUT " $subname\t$postponed{$subname}\n";
			  last if $signal;
			}
		      }
		      my @have = map { # Combined keys
			keys %{$postponed_file{$_}}
		      } keys %postponed_file;
		      if (@have) {
			print $OUT "Postponed breakpoints in files:\n";
			my ($file, $line);
			for $file (keys %postponed_file) {
			  my $db = $postponed_file{$file};
			  print $OUT " $file:\n";
			  for $line (sort {$a <=> $b} keys %$db) {
				print $OUT "  $line:\n";
				my ($stop,$action) = split(/\0/, $$db{$line});
				print $OUT "    break if (", $stop, ")\n"
				  if $stop;
				print $OUT "    action:  ", $action, "\n"
				  if $action;
				last if $signal;
			  }
			  last if $signal;
			}
		      }
		      if (%break_on_load) {
			print $OUT "Breakpoints on load:\n";
			my $file;
			for $file (keys %break_on_load) {
			  print $OUT " $file\n";
			  last if $signal;
			}
		      }
		      next CMD; };
		    $cmd =~ /^b\b\s*load\b\s*(.*)/ && do {
			my $file = $1; $file =~ s/\s+$//;
			{
			  $break_on_load{$file} = 1;
			  $break_on_load{$::INC{$file}} = 1 if $::INC{$file};
			  $file .= '.pm', redo unless $file =~ /\./;
			}
			$had_breakpoints{$file} = 1;
			print $OUT "Will stop on load of `@{[join '\', `', sort keys %break_on_load]}'.\n";
			next CMD; };
		    $cmd =~ /^b\b\s*(postpone|compile)\b\s*([':A-Za-z_][':\w]*)\s*(.*)/ && do {
			my $cond = $3 || '1';
			my ($subname, $break) = ($2, $1 eq 'postpone');
			$subname =~ s/\'/::/;
			$subname = "${'package'}::" . $subname
			  unless $subname =~ /::/;
			$subname = "main".$subname if substr($subname,0,2) eq "::";
			$postponed{$subname} = $break 
			  ? "break +0 if $cond" : "compile";
			next CMD; };
		    $cmd =~ /^b\b\s*([':A-Za-z_][':\w]*)\s*(.*)/ && do {
			$subname = $1;
			$cond = $2 || '1';
			$subname =~ s/\'/::/;
			$subname = "${'package'}::" . $subname
			  unless $subname =~ /::/;
			$subname = "main".$subname if substr($subname,0,2) eq "::";
			# Filename below can contain ':'
			($file,$i) = (find_sub($subname) =~ /^(.*):(.*)$/);
			$i += 0;
			if ($i) {
			    $filename = $file;
			    *dbline = $main::{'_<' . $filename};
			    $had_breakpoints{$filename} = 1;
			    $max = $#dbline;
			    ++$i while $dbline[$i] == 0 && $i < $max;
			    $dbline{$i} =~ s/^[^\0]*/$cond/;
			} else {
			    print $OUT "Subroutine $subname not found.\n";
			}
			next CMD; };
		    $cmd =~ /^b\b\s*(\d*)\s*(.*)/ && do {
			$i = ($1?$1:$line);
			$cond = $2 || '1';
			if ($dbline[$i] == 0) {
			    print $OUT "Line $i not breakable.\n";
			} else {
			    $had_breakpoints{$filename} = 1;
			    $dbline{$i} =~ s/^[^\0]*/$cond/;
			}
			next CMD; };
		    $cmd =~ /^d\b\s*(\d+)?/ && do {
			$i = ($1?$1:$line);
			$dbline{$i} =~ s/^[^\0]*//;
			delete $dbline{$i} if $dbline{$i} eq '';
			next CMD; };
		    $cmd =~ /^A$/ && do {
		      my $file;
		      for $file (keys %had_breakpoints) {
			local *dbline = $main::{'_<' . $file};
			my $max = $#dbline;
			my $was;
			
			for ($i = 1; $i <= $max ; $i++) {
			    if (defined $dbline{$i}) {
				$dbline{$i} =~ s/\0[^\0]*//;
				delete $dbline{$i} if $dbline{$i} eq '';
			    }
			}
		      }
		      next CMD; };
		    $cmd =~ /^O\s*$/ && do {
			for (@options) {
			    &dump_option($_);
			}
			next CMD; };
		    $cmd =~ /^O\s*(\S.*)/ && do {
			parse_options($1);
			next CMD; };
		    $cmd =~ /^\<\<\s*(.*)/ && do { # \<\< for CPerl sake: not HERE
			push @$pre, action($1);
			next CMD; };
		    $cmd =~ /^>>\s*(.*)/ && do {
			push @$post, action($1);
			next CMD; };
		    $cmd =~ /^<\s*(.*)/ && do {
		        $pre = [], next CMD unless $1;
			$pre = [action($1)];
			next CMD; };
		    $cmd =~ /^>\s*(.*)/ && do {
		        $post = [], next CMD unless $1;
			$post = [action($1)];
			next CMD; };
		    $cmd =~ /^\{\{\s*(.*)/ && do {
			push @$pretype, $1;
			next CMD; };
		    $cmd =~ /^\{\s*(.*)/ && do {
		        $pretype = [], next CMD unless $1;
			$pretype = [$1];
			next CMD; };
		    $cmd =~ /^a\b\s*(\d+)(\s+(.*))?/ && do {
			$i = $1; $j = $3;
			if ($dbline[$i] == 0) {
			    print $OUT "Line $i may not have an action.\n";
			} else {
			    $dbline{$i} =~ s/\0[^\0]*//;
			    $dbline{$i} .= "\0" . action($j);
			}
			next CMD; };
		    $cmd =~ /^n$/ && do {
		        end_report(), next CMD if $finished and $level <= 1;
			$single = 2;
			$laststep = $cmd;
			last CMD; };
		    $cmd =~ /^s$/ && do {
		        end_report(), next CMD if $finished and $level <= 1;
			$single = 1;
			$laststep = $cmd;
			last CMD; };
		    $cmd =~ /^c\b\s*([\w:]*)\s*$/ && do {
		        end_report(), next CMD if $finished and $level <= 1;
			$i = $1;
			if ($i =~ /\D/) { # subroutine name
			    ($file,$i) = (find_sub($i) =~ /^(.*):(.*)$/);
			    $i += 0;
			    if ($i) {
			        $filename = $file;
				*dbline = $main::{'_<' . $filename};
				$had_breakpoints{$filename}++;
				$max = $#dbline;
				++$i while $dbline[$i] == 0 && $i < $max;
			    } else {
				print $OUT "Subroutine $subname not found.\n";
				next CMD; 
			    }
			}
			if ($i) {
			    if ($dbline[$i] == 0) {
				print $OUT "Line $i not breakable.\n";
				next CMD;
			    }
			    $dbline{$i} =~ s/($|\0)/;9$1/; # add one-time-only b.p.
			}
			for ($i=0; $i <= $#stack; ) {
			    $stack[$i++] &= ~1;
			}
			last CMD; };
		    $cmd =~ /^r$/ && do {
		        end_report(), next CMD if $finished and $level <= 1;
			$stack[$#stack] |= 1;
			$doret = $option{PrintRet} ? $#stack - 1 : -2;
			last CMD; };
		    $cmd =~ /^R$/ && do {
		        print $OUT "Warning: some settings and command-line options may be lost!\n";
			my (@script, @flags, $cl);
			push @flags, '-w' if $ini_warn;
			# Put all the old includes at the start to get
			# the same debugger.
			for (@ini_INC) {
			  push @flags, '-I', $_;
			}
			# Arrange for setting the old INC:
			set_list("PERLDB_INC", @ini_INC);
			if ($0 eq '-e') {
			  for (1..$#{'::_<-e'}) { # The first line is PERL5DB
			    chomp ($cl =  $ {'::_<-e'}[$_]);
			    push @script, '-e', $cl;
			  }
			} else {
			  @script = $0;
			}
			set_list("PERLDB_HIST", 
				 $term->Features->{getHistory} 
				 ? $term->GetHistory : @hist);
			my @had_breakpoints = keys %had_breakpoints;
			set_list("PERLDB_VISITED", @had_breakpoints);
			set_list("PERLDB_OPT", %option);
			set_list("PERLDB_ON_LOAD", %break_on_load);
			my @hard;
			for (0 .. $#had_breakpoints) {
			  my $file = $had_breakpoints[$_];
			  *dbline = $main::{'_<' . $file};
			  next unless %dbline or $postponed_file{$file};
			  (push @hard, $file), next 
			    if $file =~ /^\(eval \d+\)$/;
			  my @add;
			  @add = %{$postponed_file{$file}}
			    if $postponed_file{$file};
			  set_list("PERLDB_FILE_$_", %dbline, @add);
			}
			for (@hard) { # Yes, really-really...
			  # Find the subroutines in this eval
			  *dbline = $main::{'_<' . $_};
			  my ($quoted, $sub, %subs, $line) = quotemeta $_;
			  for $sub (keys %sub) {
			    next unless $sub{$sub} =~ /^$quoted:(\d+)-(\d+)$/;
			    $subs{$sub} = [$1, $2];
			  }
			  unless (%subs) {
			    print $OUT
			      "No subroutines in $_, ignoring breakpoints.\n";
			    next;
			  }
			LINES: for $line (keys %dbline) {
			    # One breakpoint per sub only:
			    my ($offset, $sub, $found);
			  SUBS: for $sub (keys %subs) {
			      if ($subs{$sub}->[1] >= $line # Not after the subroutine
				  and (not defined $offset # Not caught
				       or $offset < 0 )) { # or badly caught
				$found = $sub;
				$offset = $line - $subs{$sub}->[0];
				$offset = "+$offset", last SUBS if $offset >= 0;
			      }
			    }
			    if (defined $offset) {
			      $postponed{$found} =
				"break $offset if $dbline{$line}";
			    } else {
			      print $OUT "Breakpoint in $_:$line ignored: after all the subroutines.\n";
			    }
			  }
			}
			set_list("PERLDB_POSTPONE", %postponed);
			set_list("PERLDB_PRETYPE", @$pretype);
			set_list("PERLDB_PRE", @$pre);
			set_list("PERLDB_POST", @$post);
			set_list("PERLDB_TYPEAHEAD", @typeahead);
			$ENV{PERLDB_RESTART} = 1;
			#print "$^X, '-d', @flags, @script, ($emacs ? '-emacs' : ()), @ARGS";
			exec $^X, '-d', @flags, @script, ($emacs ? '-emacs' : ()), @ARGS;
			print $OUT "exec failed: $!\n";
			last CMD; };
		    $cmd =~ /^T$/ && do {
			print_trace($OUT, 1); # skip DB
			next CMD; };
		    $cmd =~ /^\/(.*)$/ && do {
			$inpat = $1;
			$inpat =~ s:([^\\])/$:$1:;
			if ($inpat ne "") {
			    eval '$inpat =~ m'."\a$inpat\a";	
			    if ($@ ne "") {
				print $OUT "$@";
				next CMD;
			    }
			    $pat = $inpat;
			}
			$end = $start;
			$incr = -1;
			eval '
			    for (;;) {
				++$start;
				$start = 1 if ($start > $max);
				last if ($start == $end);
				if ($dbline[$start] =~ m' . "\a$pat\a" . 'i) {
				    if ($emacs) {
					print $OUT "\032\032$filename:$start:0\n";
				    } else {
					print $OUT "$start:\t", $dbline[$start], "\n";
				    }
				    last;
				}
			    } ';
			print $OUT "/$pat/: not found\n" if ($start == $end);
			next CMD; };
		    $cmd =~ /^\?(.*)$/ && do {
			$inpat = $1;
			$inpat =~ s:([^\\])\?$:$1:;
			if ($inpat ne "") {
			    eval '$inpat =~ m'."\a$inpat\a";	
			    if ($@ ne "") {
				print $OUT "$@";
				next CMD;
			    }
			    $pat = $inpat;
			}
			$end = $start;
			$incr = -1;
			eval '
			    for (;;) {
				--$start;
				$start = $max if ($start <= 0);
				last if ($start == $end);
				if ($dbline[$start] =~ m' . "\a$pat\a" . 'i) {
				    if ($emacs) {
					print $OUT "\032\032$filename:$start:0\n";
				    } else {
					print $OUT "$start:\t", $dbline[$start], "\n";
				    }
				    last;
				}
			    } ';
			print $OUT "?$pat?: not found\n" if ($start == $end);
			next CMD; };
		    $cmd =~ /^$rc+\s*(-)?(\d+)?$/ && do {
			pop(@hist) if length($cmd) > 1;
			$i = $1 ? ($#hist-($2?$2:1)) : ($2?$2:$#hist);
			$cmd = $hist[$i] . "\n";
			print $OUT $cmd;
			redo CMD; };
		    $cmd =~ /^$sh$sh\s*([\x00-\xff]*)/ && do {
			&system($1);
			next CMD; };
		    $cmd =~ /^$rc([^$rc].*)$/ && do {
			$pat = "^$1";
			pop(@hist) if length($cmd) > 1;
			for ($i = $#hist; $i; --$i) {
			    last if $hist[$i] =~ /$pat/;
			}
			if (!$i) {
			    print $OUT "No such command!\n\n";
			    next CMD;
			}
			$cmd = $hist[$i] . "\n";
			print $OUT $cmd;
			redo CMD; };
		    $cmd =~ /^$sh$/ && do {
			&system($ENV{SHELL}||"/bin/sh");
			next CMD; };
		    $cmd =~ /^$sh\s*([\x00-\xff]*)/ && do {
			&system($ENV{SHELL}||"/bin/sh","-c",$1);
			next CMD; };
		    $cmd =~ /^H\b\s*(-(\d+))?/ && do {
			$end = $2?($#hist-$2):0;
			$hist = 0 if $hist < 0;
			for ($i=$#hist; $i>$end; $i--) {
			    print $OUT "$i: ",$hist[$i],"\n"
			      unless $hist[$i] =~ /^.?$/;
			};
			next CMD; };
		    $cmd =~ s/^p$/print {\$DB::OUT} \$_/;
		    $cmd =~ s/^p\b/print {\$DB::OUT} /;
		    $cmd =~ /^=/ && do {
			if (local($k,$v) = ($cmd =~ /^=\s*(\S+)\s+(.*)/)) {
			    $alias{$k}="s~$k~$v~";
			    print $OUT "$k = $v\n";
			} elsif ($cmd =~ /^=\s*$/) {
			    foreach $k (sort keys(%alias)) {
				if (($v = $alias{$k}) =~ s~^s\~$k\~(.*)\~$~$1~) {
				    print $OUT "$k = $v\n";
				} else {
				    print $OUT "$k\t$alias{$k}\n";
				};
			    };
			};
			next CMD; };
		    $cmd =~ /^\|\|?\s*[^|]/ && do {
			if ($pager =~ /^\|/) {
			    open(SAVEOUT,">&STDOUT") || &warn("Can't save STDOUT");
			    open(STDOUT,">&OUT") || &warn("Can't redirect STDOUT");
			} else {
			    open(SAVEOUT,">&OUT") || &warn("Can't save DB::OUT");
			}
			unless ($piped=open(OUT,$pager)) {
			    &warn("Can't pipe output to `$pager'");
			    if ($pager =~ /^\|/) {
				open(OUT,">&STDOUT") || &warn("Can't restore DB::OUT");
				open(STDOUT,">&SAVEOUT")
				  || &warn("Can't restore STDOUT");
				close(SAVEOUT);
			    } else {
				open(OUT,">&STDOUT") || &warn("Can't restore DB::OUT");
			    }
			    next CMD;
			}
			$SIG{PIPE}= \&DB::catch if $pager =~ /^\|/
			  && "" eq $SIG{PIPE}  ||  "DEFAULT" eq $SIG{PIPE};
			$selected= select(OUT);
			$|= 1;
			select( $selected ), $selected= "" unless $cmd =~ /^\|\|/;
			$cmd =~ s/^\|+\s*//;
			redo PIPE; };
		    # XXX Local variants do not work!
		    $cmd =~ s/^t\s/\$DB::trace = 1;\n/;
		    $cmd =~ s/^s\s/\$DB::single = 1;\n/ && do {$laststep = 's'};
		    $cmd =~ s/^n\s/\$DB::single = 2;\n/ && do {$laststep = 'n'};
		}		# PIPE:
	    $evalarg = "\$^D = \$^D | \$DB::db_stop;\n$cmd"; &eval;
	    if ($onetimeDump) {
		$onetimeDump = undef;
	    } else {
		print $OUT "\n";
	    }
	} continue {		# CMD:
	    if ($piped) {
		if ($pager =~ /^\|/) {
		    $?= 0;  close(OUT) || &warn("Can't close DB::OUT");
		    &warn( "Pager `$pager' failed: ",
			  ($?>>8) > 128 ? ($?>>8)-256 : ($?>>8),
			  ( $? & 128 ) ? " (core dumped)" : "",
			  ( $? & 127 ) ? " (SIG ".($?&127).")" : "", "\n" ) if $?;
		    open(OUT,">&STDOUT") || &warn("Can't restore DB::OUT");
		    open(STDOUT,">&SAVEOUT") || &warn("Can't restore STDOUT");
		    $SIG{PIPE}= "DEFAULT" if $SIG{PIPE} eq \&DB::catch;
		    # Will stop ignoring SIGPIPE if done like nohup(1)
		    # does SIGINT but Perl doesn't give us a choice.
		} else {
		    open(OUT,">&SAVEOUT") || &warn("Can't restore DB::OUT");
		}
		close(SAVEOUT);
		select($selected), $selected= "" unless $selected eq "";
		$piped= "";
	    }
	}			# CMD:
	$exiting = 1 unless defined $cmd;
	foreach $evalarg (@$post) {
	  &eval;
	}
    }				# if ($single || $signal)
    ($@, $!, $,, $/, $\, $^W) = @saved;
    ();
}

# The following code may be executed now:
# BEGIN {warn 4}

sub sub {
    my ($al, $ret, @ret) = "";
    if (length($sub) > 10 && substr($sub, -10, 10) eq '::AUTOLOAD') {
	$al = " for $$sub";
    }
    push(@stack, $single);
    $single &= 1;
    $single |= 4 if $#stack == $deep;
    ($frame & 4 
     ? ( (print $LINEINFO ' ' x ($#stack - 1), "in  "), 
	 # Why -1? But it works! :-(
	 print_trace($LINEINFO, -1, 1, 1, "$sub$al") )
     : print $LINEINFO ' ' x ($#stack - 1), "entering $sub$al\n") if $frame;
    if (wantarray) {
	@ret = &$sub;
	$single |= pop(@stack);
	($frame & 4 
	 ? ( (print $LINEINFO ' ' x $#stack, "out "), 
	     print_trace($LINEINFO, -1, 1, 1, "$sub$al") )
	 : print $LINEINFO ' ' x $#stack, "exited $sub$al\n") if $frame & 2;
	print ($OUT ($frame & 16 ? ' ' x $#stack : ""),
		    "list context return from $sub:\n"), dumpit( \@ret ),
	  $doret = -2 if $doret eq $#stack or $frame & 16;
	@ret;
    } else {
	$ret = &$sub;
	$single |= pop(@stack);
	($frame & 4 
	 ? ( (print $LINEINFO ' ' x $#stack, "out "), 
	      print_trace($LINEINFO, -1, 1, 1, "$sub$al") )
	 : print $LINEINFO ' ' x $#stack, "exited $sub$al\n") if $frame & 2;
	print ($OUT ($frame & 16 ? ' ' x $#stack : ""),
		    "scalar context return from $sub: "), dumpit( $ret ),
	  $doret = -2 if $doret eq $#stack or $frame & 16;
	$ret;
    }
}

sub save {
    @saved = ($@, $!, $,, $/, $\, $^W);
    $, = ""; $/ = "\n"; $\ = ""; $^W = 0;
}

# The following takes its argument via $evalarg to preserve current @_

sub eval {
    my @res;
    {
	local (@stack) = @stack; # guard against recursive debugging
	my $otrace = $trace;
	my $osingle = $single;
	my $od = $^D;
	@res = eval "$usercontext $evalarg;\n"; # '\n' for nice recursive debug
	$trace = $otrace;
	$single = $osingle;
	$^D = $od;
    }
    my $at = $@;
    local $saved[0];		# Preserve the old value of $@
    eval "&DB::save";
    if ($at) {
	print $OUT $at;
    } elsif ($onetimeDump eq 'dump') {
	dumpit(\@res);
    } elsif ($onetimeDump eq 'methods') {
	methods($res[0]);
    }
}

sub postponed_sub {
  my $subname = shift;
  if ($postponed{$subname} =~ s/^break\s([+-]?\d+)\s+if\s//) {
    my $offset = $1 || 0;
    # Filename below can contain ':'
    my ($file,$i) = (find_sub($subname) =~ /^(.*):(\d+)-.*$/);
    $i += $offset;
    if ($i) {
      local *dbline = $main::{'_<' . $file};
      local $^W = 0;		# != 0 is magical below
      $had_breakpoints{$file}++;
      my $max = $#dbline;
      ++$i until $dbline[$i] != 0 or $i >= $max;
      $dbline{$i} = delete $postponed{$subname};
    } else {
      print $OUT "Subroutine $subname not found.\n";
    }
    return;
  }
  elsif ($postponed{$subname} eq 'compile') { $signal = 1 }
  #print $OUT "In postponed_sub for `$subname'.\n";
}

sub postponed {
  return &postponed_sub
    unless ref \$_[0] eq 'GLOB'; # A subroutine is compiled.
  # Cannot be done before the file is compiled
  local *dbline = shift;
  my $filename = $dbline;
  $filename =~ s/^_<//;
  $signal = 1, print $OUT "'$filename' loaded...\n"
    if $break_on_load{$filename};
  print $LINEINFO ' ' x $#stack, "Package $filename.\n" if $frame;
  return unless $postponed_file{$filename};
  $had_breakpoints{$filename}++;
  #%dbline = %{$postponed_file{$filename}}; # Cannot be done: unsufficient magic
  my $key;
  for $key (keys %{$postponed_file{$filename}}) {
    $dbline{$key} = $ {$postponed_file{$filename}}{$key};
  }
  delete $postponed_file{$filename};
}

sub dumpit {
    local ($savout) = select($OUT);
    my $osingle = $single;
    my $otrace = $trace;
    $single = $trace = 0;
    local $frame = 0;
    local $doret = -2;
    unless (defined &main::dumpValue) {
	do 'dumpvar.pl';
    }
    if (defined &main::dumpValue) {
	&main::dumpValue(shift);
    } else {
	print $OUT "dumpvar.pl not available.\n";
    }
    $single = $osingle;
    $trace = $otrace;
    select ($savout);    
}

# Tied method do not create a context, so may get wrong message:

sub print_trace {
  my $fh = shift;
  my @sub = dump_trace($_[0] + 1, $_[1]);
  my $short = $_[2];		# Print short report, next one for sub name
  my $s;
  for ($i=0; $i <= $#sub; $i++) {
    last if $signal;
    local $" = ', ';
    my $args = defined $sub[$i]{args} 
    ? "(@{ $sub[$i]{args} })"
      : '' ;
    $args = (substr $args, 0, $maxtrace - 3) . '...' 
      if length $args > $maxtrace;
    my $file = $sub[$i]{file};
    $file = $file eq '-e' ? $file : "file `$file'" unless $short;
    $s = $sub[$i]{sub};
    $s = (substr $s, 0, $maxtrace - 3) . '...' if length $s > $maxtrace;    
    if ($short) {
      my $sub = @_ >= 4 ? $_[3] : $s;
      print $fh "$sub[$i]{context}=$sub$args from $file:$sub[$i]{line}\n";
    } else {
      print $fh "$sub[$i]{context} = $s$args" .
	" called from $file" . 
	  " line $sub[$i]{line}\n";
    }
  }
}

sub dump_trace {
  my $skip = shift;
  my $count = shift || 1e9;
  $skip++;
  $count += $skip;
  my ($p,$file,$line,$sub,$h,$args,$e,$r,@a,@sub,$context);
  my $nothard = not $frame & 8;
  local $frame = 0;		# Do not want to trace this.
  my $otrace = $trace;
  $trace = 0;
  for ($i = $skip; 
       $i < $count and ($p,$file,$line,$sub,$h,$context,$e,$r) = caller($i); 
       $i++) {
    @a = ();
    for $arg (@args) {
      my $type;
      if (not defined $arg) {
	push @a, "undef";
      } elsif ($nothard and tied $arg) {
	push @a, "tied";
      } elsif ($nothard and $type = ref $arg) {
	push @a, "ref($type)";
      } else {
	local $_ = "$arg";	# Safe to stringify now - should not call f().
	s/([\'\\])/\\$1/g;
	s/(.*)/'$1'/s
	  unless /^(?: -?[\d.]+ | \*[\w:]* )$/x;
	s/([\200-\377])/sprintf("M-%c",ord($1)&0177)/eg;
	s/([\0-\37\177])/sprintf("^%c",ord($1)^64)/eg;
	push(@a, $_);
      }
    }
    $context = $context ? '@' : "\$";
    $args = $h ? [@a] : undef;
    $e =~ s/\n\s*\;\s*\Z// if $e;
    $e =~ s/([\\\'])/\\$1/g if $e;
    if ($r) {
      $sub = "require '$e'";
    } elsif (defined $r) {
      $sub = "eval '$e'";
    } elsif ($sub eq '(eval)') {
      $sub = "eval {...}";
    }
    push(@sub, {context => $context, sub => $sub, args => $args,
		file => $file, line => $line});
    last if $signal;
  }
  $trace = $otrace;
  @sub;
}

sub action {
    my $action = shift;
    while ($action =~ s/\\$//) {
	#print $OUT "+ ";
	#$action .= "\n";
	$action .= &gets;
    }
    $action;
}

sub gets {
    local($.);
    #<IN>;
    &readline("cont: ");
}

sub system {
    # We save, change, then restore STDIN and STDOUT to avoid fork() since
    # many non-Unix systems can do system() but have problems with fork().
    open(SAVEIN,"<&STDIN") || &warn("Can't save STDIN");
    open(SAVEOUT,">&OUT") || &warn("Can't save STDOUT");
    open(STDIN,"<&IN") || &warn("Can't redirect STDIN");
    open(STDOUT,">&OUT") || &warn("Can't redirect STDOUT");
    system(@_);
    open(STDIN,"<&SAVEIN") || &warn("Can't restore STDIN");
    open(STDOUT,">&SAVEOUT") || &warn("Can't restore STDOUT");
    close(SAVEIN); close(SAVEOUT);
    &warn( "(Command returned ", ($?>>8) > 128 ? ($?>>8)-256 : ($?>>8), ")",
	  ( $? & 128 ) ? " (core dumped)" : "",
	  ( $? & 127 ) ? " (SIG ".($?&127).")" : "", "\n" ) if $?;
    $?;
}

sub setterm {
    local $frame = 0;
    local $doret = -2;
    local @stack = @stack;		# Prevent growth by failing `use'.
    eval { require Term::ReadLine } or die $@;
    if ($notty) {
	if ($tty) {
	    open(IN,"<$tty") or die "Cannot open TTY `$TTY' for read: $!";
	    open(OUT,">$tty") or die "Cannot open TTY `$TTY' for write: $!";
	    $IN = \*IN;
	    $OUT = \*OUT;
	    my $sel = select($OUT);
	    $| = 1;
	    select($sel);
	} else {
	    eval "require Term::Rendezvous;" or die $@;
	    my $rv = $ENV{PERLDB_NOTTY} || "/tmp/perldbtty$$";
	    my $term_rv = new Term::Rendezvous $rv;
	    $IN = $term_rv->IN;
	    $OUT = $term_rv->OUT;
	}
    }
    if (!$rl) {
	$term = new Term::ReadLine::Stub 'perldb', $IN, $OUT;
    } else {
	$term = new Term::ReadLine 'perldb', $IN, $OUT;

	$rl_attribs = $term->Attribs;
	$rl_attribs->{basic_word_break_characters} .= '-:+/*,[])}' 
	  if defined $rl_attribs->{basic_word_break_characters} 
	    and index($rl_attribs->{basic_word_break_characters}, ":") == -1;
	$rl_attribs->{special_prefixes} = '$@&%';
	$rl_attribs->{completer_word_break_characters} .= '$@&%';
	$rl_attribs->{completion_function} = \&db_complete; 
    }
    $LINEINFO = $OUT unless defined $LINEINFO;
    $lineinfo = $console unless defined $lineinfo;
    $term->MinLine(2);
    if ($term->Features->{setHistory} and "@hist" ne "?") {
      $term->SetHistory(@hist);
    }
    ornaments($ornaments) if defined $ornaments;
}

sub readline {
  if (@typeahead) {
    my $left = @typeahead;
    my $got = shift @typeahead;
    print $OUT "auto(-$left)", shift, $got, "\n";
    $term->AddHistory($got) 
      if length($got) > 1 and defined $term->Features->{addHistory};
    return $got;
  }
  local $frame = 0;
  local $doret = -2;
  $term->readline(@_);
}

sub dump_option {
    my ($opt, $val)= @_;
    $val = option_val($opt,'N/A');
    $val =~ s/([\\\'])/\\$1/g;
    printf $OUT "%20s = '%s'\n", $opt, $val;
}

sub option_val {
    my ($opt, $default)= @_;
    my $val;
    if (defined $optionVars{$opt}
	and defined $ {$optionVars{$opt}}) {
	$val = $ {$optionVars{$opt}};
    } elsif (defined $optionAction{$opt}
	and defined &{$optionAction{$opt}}) {
	$val = &{$optionAction{$opt}}();
    } elsif (defined $optionAction{$opt}
	     and not defined $option{$opt}
	     or defined $optionVars{$opt}
	     and not defined $ {$optionVars{$opt}}) {
	$val = $default;
    } else {
	$val = $option{$opt};
    }
    $val
}

sub parse_options {
    local($_)= @_;
    while ($_ ne "") {
	s/^(\w+)(\s*$|\W)// or print($OUT "Invalid option `$_'\n"), last;
	my ($opt,$sep) = ($1,$2);
	my $val;
	if ("?" eq $sep) {
	    print($OUT "Option query `$opt?' followed by non-space `$_'\n"), last
	      if /^\S/;
	    #&dump_option($opt);
	} elsif ($sep !~ /\S/) {
	    $val = "1";
	} elsif ($sep eq "=") {
	    s/^(\S*)($|\s+)//;
	    $val = $1;
	} else { #{ to "let some poor schmuck bounce on the % key in B<vi>."
	    my ($end) = "\\" . substr( ")]>}$sep", index("([<{",$sep), 1 ); #}
	    s/^(([^\\$end]|\\[\\$end])*)$end($|\s+)// or
	      print($OUT "Unclosed option value `$opt$sep$_'\n"), last;
	    $val = $1;
	    $val =~ s/\\([\\$end])/$1/g;
	}
	my ($option);
	my $matches =
	  grep(  /^\Q$opt/ && ($option = $_),  @options  );
	$matches =  grep(  /^\Q$opt/i && ($option = $_),  @options  )
	  unless $matches;
	print $OUT "Unknown option `$opt'\n" unless $matches;
	print $OUT "Ambiguous option `$opt'\n" if $matches > 1;
	$option{$option} = $val if $matches == 1 and defined $val;
	eval "local \$frame = 0; local \$doret = -2; 
	      require '$optionRequire{$option}'"
	  if $matches == 1 and defined $optionRequire{$option} and defined $val;
	$ {$optionVars{$option}} = $val 
	  if $matches == 1
	    and defined $optionVars{$option} and defined $val;
	& {$optionAction{$option}} ($val) 
	  if $matches == 1
	    and defined $optionAction{$option}
	      and defined &{$optionAction{$option}} and defined $val;
	&dump_option($option) if $matches == 1 && $OUT ne \*STDERR; # Not $rcfile
        s/^\s+//;
    }
}

sub set_list {
  my ($stem,@list) = @_;
  my $val;
  $ENV{"$ {stem}_n"} = @list;
  for $i (0 .. $#list) {
    $val = $list[$i];
    $val =~ s/\\/\\\\/g;
    $val =~ s/([\0-\37\177\200-\377])/"\\0x" . unpack('H2',$1)/eg;
    $ENV{"$ {stem}_$i"} = $val;
  }
}

sub get_list {
  my $stem = shift;
  my @list;
  my $n = delete $ENV{"$ {stem}_n"};
  my $val;
  for $i (0 .. $n - 1) {
    $val = delete $ENV{"$ {stem}_$i"};
    $val =~ s/\\((\\)|0x(..))/ $2 ? $2 : pack('H2', $3) /ge;
    push @list, $val;
  }
  @list;
}

sub catch {
    $signal = 1;
    return;			# Put nothing on the stack - malloc/free land!
}

sub warn {
    my($msg)= join("",@_);
    $msg .= ": $!\n" unless $msg =~ /\n$/;
    print $OUT $msg;
}

sub TTY {
    if ($term) {
	&warn("Too late to set TTY, enabled on next `R'!\n") if @_;
    } 
    $tty = shift if @_;
    $tty or $console;
}

sub noTTY {
    if ($term) {
	&warn("Too late to set noTTY, enabled on next `R'!\n") if @_;
    }
    $notty = shift if @_;
    $notty;
}

sub ReadLine {
    if ($term) {
	&warn("Too late to set ReadLine, enabled on next `R'!\n") if @_;
    }
    $rl = shift if @_;
    $rl;
}

sub tkRunning {
    if ($ {$term->Features}{tkRunning}) {
        return $term->tkRunning(@_);
    } else {
	print $OUT "tkRunning not supported by current ReadLine package.\n";
	0;
    }
}

sub NonStop {
    if ($term) {
	&warn("Too late to set up NonStop mode, enabled on next `R'!\n") if @_;
    }
    $runnonstop = shift if @_;
    $runnonstop;
}

sub pager {
    if (@_) {
	$pager = shift;
	$pager="|".$pager unless $pager =~ /^(\+?\>|\|)/;
    }
    $pager;
}

sub shellBang {
    if (@_) {
	$sh = quotemeta shift;
	$sh .= "\\b" if $sh =~ /\w$/;
    }
    $psh = $sh;
    $psh =~ s/\\b$//;
    $psh =~ s/\\(.)/$1/g;
    &sethelp;
    $psh;
}

sub ornaments {
  if (defined $term) {
    local ($warnLevel,$dieLevel) = (0, 1);
    return '' unless $term->Features->{ornaments};
    eval { $term->ornaments(@_) } || '';
  } else {
    $ornaments = shift;
  }
}

sub recallCommand {
    if (@_) {
	$rc = quotemeta shift;
	$rc .= "\\b" if $rc =~ /\w$/;
    }
    $prc = $rc;
    $prc =~ s/\\b$//;
    $prc =~ s/\\(.)/$1/g;
    &sethelp;
    $prc;
}

sub LineInfo {
    return $lineinfo unless @_;
    $lineinfo = shift;
    my $stream = ($lineinfo =~ /^(\+?\>|\|)/) ? $lineinfo : ">$lineinfo";
    $emacs = ($stream =~ /^\|/);
    open(LINEINFO, "$stream") || &warn("Cannot open `$stream' for write");
    $LINEINFO = \*LINEINFO;
    my $save = select($LINEINFO);
    $| = 1;
    select($save);
    $lineinfo;
}

sub list_versions {
  my %version;
  my $file;
  for (keys %INC) {
    $file = $_;
    s,\.p[lm]$,,i ;
    s,/,::,g ;
    s/^perl5db$/DB/;
    s/^Term::ReadLine::readline$/readline/;
    if (defined $ { $_ . '::VERSION' }) {
      $version{$file} = "$ { $_ . '::VERSION' } from ";
    } 
    $version{$file} .= $INC{$file};
  }
  do 'dumpvar.pl' unless defined &main::dumpValue;
  if (defined &main::dumpValue) {
    local $frame = 0;
    &main::dumpValue(\%version);
  } else {
    print $OUT "dumpvar.pl not available.\n";
  }
}

sub sethelp {
    $help = "
T		Stack trace.
s [expr]	Single step [in expr].
n [expr]	Next, steps over subroutine calls [in expr].
<CR>		Repeat last n or s command.
r		Return from current subroutine.
c [line|sub]	Continue; optionally inserts a one-time-only breakpoint
		at the specified position.
l min+incr	List incr+1 lines starting at min.
l min-max	List lines min through max.
l line		List single line.
l subname	List first window of lines from subroutine.
l		List next window of lines.
-		List previous window of lines.
w [line]	List window around line.
.		Return to the executed line.
f filename	Switch to viewing filename. Must be loaded.
/pattern/	Search forwards for pattern; final / is optional.
?pattern?	Search backwards for pattern; final ? is optional.
L		List all breakpoints and actions.
S [[!]pattern]	List subroutine names [not] matching pattern.
t		Toggle trace mode.
t expr		Trace through execution of expr.
b [line] [condition]
		Set breakpoint; line defaults to the current execution line;
		condition breaks if it evaluates to true, defaults to '1'.
b subname [condition]
		Set breakpoint at first line of subroutine.
b load filename Set breakpoint on `require'ing the given file.
b postpone subname [condition]
		Set breakpoint at first line of subroutine after 
		it is compiled.
b compile subname
		Stop after the subroutine is compiled.
d [line]	Delete the breakpoint for line.
D		Delete all breakpoints.
a [line] command
		Set an action to be done before the line is executed.
		Sequence is: check for breakpoint, print line if necessary,
		do action, prompt user if breakpoint or step, evaluate line.
A		Delete all actions.
V [pkg [vars]]	List some (default all) variables in package (default current).
		Use ~pattern and !pattern for positive and negative regexps.
X [vars]	Same as \"V currentpackage [vars]\".
x expr		Evals expression in array context, dumps the result.
m expr		Evals expression in array context, prints methods callable
		on the first element of the result.
m class		Prints methods callable via the given class.
O [opt[=val]] [opt\"val\"] [opt?]...
		Set or query values of options.  val defaults to 1.  opt can
		be abbreviated.  Several options can be listed.
    recallCommand, ShellBang:	chars used to recall command or spawn shell;
    pager:			program for output of \"|cmd\";
    tkRunning:			run Tk while prompting (with ReadLine);
    signalLevel warnLevel dieLevel:	level of verbosity;
    inhibit_exit		Allows stepping off the end of the script.
  The following options affect what happens with V, X, and x commands:
    arrayDepth, hashDepth:	print only first N elements ('' for all);
    compactDump, veryCompact:	change style of array and hash dump;
    globPrint:			whether to print contents of globs;
    DumpDBFiles:		dump arrays holding debugged files;
    DumpPackages:		dump symbol tables of packages;
    quote, HighBit, undefPrint:	change style of string dump;
  Option PrintRet affects printing of return value after r command,
         frame    affects printing messages on entry and exit from subroutines.
         AutoTrace affects printing messages on every possible breaking point.
	 maxTraceLen gives maximal length of evals/args listed in stack trace.
	 ornaments affects screen appearance of the command line.
		During startup options are initialized from \$ENV{PERLDB_OPTS}.
		You can put additional initialization options TTY, noTTY,
		ReadLine, and NonStop there (or use `R' after you set them).
< command	Define Perl command to run before each prompt.
<< command	Add to the list of Perl commands to run before each prompt.
> command	Define Perl command to run after each prompt.
>> command	Add to the list of Perl commands to run after each prompt.
\{ commandline	Define debugger command to run before each prompt.
\{{ commandline	Add to the list of debugger commands to run before each prompt.
$prc number	Redo a previous command (default previous command).
$prc -number	Redo number'th-to-last command.
$prc pattern	Redo last command that started with pattern.
		See 'O recallCommand' too.
$psh$psh cmd  	Run cmd in a subprocess (reads from DB::IN, writes to DB::OUT)"
  . ( $rc eq $sh ? "" : "
$psh [cmd] 	Run cmd in subshell (forces \"\$SHELL -c 'cmd'\")." ) . "
		See 'O shellBang' too.
H -number	Display last number commands (default all).
p expr		Same as \"print {DB::OUT} expr\" in current package.
|dbcmd		Run debugger command, piping DB::OUT to current pager.
||dbcmd		Same as |dbcmd but DB::OUT is temporarilly select()ed as well.
\= [alias value]	Define a command alias, or list current aliases.
command		Execute as a perl statement in current package.
v		Show versions of loaded modules.
R		Pure-man-restart of debugger, some of debugger state
		and command-line options may be lost.
		Currently the following setting are preserved: 
		history, breakpoints and actions, debugger Options 
		and the following command-line options: -w, -I, -e.
h [db_command]	Get help [on a specific debugger command], enter |h to page.
h h		Summary of debugger commands.
q or ^D		Quit. Set \$DB::finished to 0 to debug global destruction.

";
    $summary = <<"END_SUM";
List/search source lines:               Control script execution:
  l [ln|sub]  List source code            T           Stack trace
  - or .      List previous/current line  s [expr]    Single step [in expr]
  w [line]    List around line            n [expr]    Next, steps over subs
  f filename  View source in file         <CR>        Repeat last n or s
  /pattern/ ?patt?   Search forw/backw    r           Return from subroutine
  v	      Show versions of modules    c [ln|sub]  Continue until position
Debugger controls:                        L           List break pts & actions
  O [...]     Set debugger options        t [expr]    Toggle trace [trace expr]
  <[<] or {[{] [cmd]   Do before prompt   b [ln/event] [c]     Set breakpoint
  >[>] [cmd]  Do after prompt             b sub [c]   Set breakpoint for sub
  $prc [N|pat]   Redo a previous command     d [line]    Delete a breakpoint
  H [-num]    Display last num commands   D           Delete all breakpoints
  = [a val]   Define/list an alias        a [ln] cmd  Do cmd before line
  h [db_cmd]  Get help on command         A           Delete all actions
  |[|]dbcmd   Send output to pager        $psh\[$psh\] syscmd Run cmd in a subprocess
  q or ^D     Quit			  R	      Attempt a restart
Data Examination:	      expr     Execute perl code, also see: s,n,t expr
  x|m expr	Evals expr in array context, dumps the result or lists methods.
  p expr	Print expression (uses script's current package).
  S [[!]pat]	List subroutine names [not] matching pattern
  V [Pk [Vars]]	List Variables in Package.  Vars can be ~pattern or !pattern.
  X [Vars]	Same as \"V current_package [Vars]\".
END_SUM
				# ')}}; # Fix balance of Emacs parsing
}

sub diesignal {
    local $frame = 0;
    local $doret = -2;
    $SIG{'ABRT'} = 'DEFAULT';
    kill 'ABRT', $$ if $panic++;
    if (defined &Carp::longmess) {
	local $SIG{__WARN__} = '';
	local $Carp::CarpLevel = 2;		# mydie + confess
	&warn(Carp::longmess("Signal @_"));
    }
    else {
	print $DB::OUT "Got signal @_\n";
    }
    kill 'ABRT', $$;
}

sub dbwarn { 
  local $frame = 0;
  local $doret = -2;
  local $SIG{__WARN__} = '';
  local $SIG{__DIE__} = '';
  eval { require Carp };	# If error/warning during compilation,
                                # require may be broken.
  warn(@_, "\nPossible unrecoverable error"), warn("\nTry to decrease warnLevel `O'ption!\n"), return
    unless defined &Carp::longmess;
  #&warn("Entering dbwarn\n");
  my ($mysingle,$mytrace) = ($single,$trace);
  $single = 0; $trace = 0;
  my $mess = Carp::longmess(@_);
  ($single,$trace) = ($mysingle,$mytrace);
  #&warn("Warning in dbwarn\n");
  &warn($mess); 
  #&warn("Exiting dbwarn\n");
}

sub dbdie {
  local $frame = 0;
  local $doret = -2;
  local $SIG{__DIE__} = '';
  local $SIG{__WARN__} = '';
  my $i = 0; my $ineval = 0; my $sub;
  #&warn("Entering dbdie\n");
  if ($dieLevel != 2) {
    while ((undef,undef,undef,$sub) = caller(++$i)) {
      $ineval = 1, last if $sub eq '(eval)';
    }
    {
      local $SIG{__WARN__} = \&dbwarn;
      &warn(@_) if $dieLevel > 2; # Ineval is false during destruction?
    }
    #&warn("dieing quietly in dbdie\n") if $ineval and $dieLevel < 2;
    die @_ if $ineval and $dieLevel < 2;
  }
  eval { require Carp };	# If error/warning during compilation,
                                # require may be broken.
  die(@_, "\nUnrecoverable error") unless defined &Carp::longmess;
  # We do not want to debug this chunk (automatic disabling works
  # inside DB::DB, but not in Carp).
  my ($mysingle,$mytrace) = ($single,$trace);
  $single = 0; $trace = 0;
  my $mess = Carp::longmess(@_);
  ($single,$trace) = ($mysingle,$mytrace);
  #&warn("dieing loudly in dbdie\n");
  die $mess;
}

sub warnLevel {
  if (@_) {
    $prevwarn = $SIG{__WARN__} unless $warnLevel;
    $warnLevel = shift;
    if ($warnLevel) {
      $SIG{__WARN__} = \&DB::dbwarn;
    } else {
      $SIG{__WARN__} = $prevwarn;
    }
  }
  $warnLevel;
}

sub dieLevel {
  if (@_) {
    $prevdie = $SIG{__DIE__} unless $dieLevel;
    $dieLevel = shift;
    if ($dieLevel) {
      $SIG{__DIE__} = \&DB::dbdie; # if $dieLevel < 2;
      #$SIG{__DIE__} = \&DB::diehard if $dieLevel >= 2;
      print $OUT "Stack dump during die enabled", 
        ( $dieLevel == 1 ? " outside of evals" : ""), ".\n"
	  if $I_m_init;
      print $OUT "Dump printed too.\n" if $dieLevel > 2;
    } else {
      $SIG{__DIE__} = $prevdie;
      print $OUT "Default die handler restored.\n";
    }
  }
  $dieLevel;
}

sub signalLevel {
  if (@_) {
    $prevsegv = $SIG{SEGV} unless $signalLevel;
    $prevbus = $SIG{BUS} unless $signalLevel;
    $signalLevel = shift;
    if ($signalLevel) {
      $SIG{SEGV} = \&DB::diesignal;
      $SIG{BUS} = \&DB::diesignal;
    } else {
      $SIG{SEGV} = $prevsegv;
      $SIG{BUS} = $prevbus;
    }
  }
  $signalLevel;
}

sub find_sub {
  my $subr = shift;
  return unless defined &$subr;
  $sub{$subr} or do {
    $subr = \&$subr;		# Hard reference
    my $s;
    for (keys %sub) {
      $s = $_, last if $subr eq \&$_;
    }
    $sub{$s} if $s;
  }
}

sub methods {
  my $class = shift;
  $class = ref $class if ref $class;
  local %seen;
  local %packs;
  methods_via($class, '', 1);
  methods_via('UNIVERSAL', 'UNIVERSAL', 0);
}

sub methods_via {
  my $class = shift;
  return if $packs{$class}++;
  my $prefix = shift;
  my $prepend = $prefix ? "via $prefix: " : '';
  my $name;
  for $name (grep {defined &{$ {"$ {class}::"}{$_}}} 
	     sort keys %{"$ {class}::"}) {
    next if $seen{ $name }++;
    print $DB::OUT "$prepend$name\n";
  }
  return unless shift;		# Recurse?
  for $name (@{"$ {class}::ISA"}) {
    $prepend = $prefix ? $prefix . " -> $name" : $name;
    methods_via($name, $prepend, 1);
  }
}

# The following BEGIN is very handy if debugger goes havoc, debugging debugger?

BEGIN {			# This does not compile, alas.
  $IN = \*STDIN;		# For bugs before DB::OUT has been opened
  $OUT = \*STDERR;		# For errors before DB::OUT has been opened
  $sh = '!';
  $rc = ',';
  @hist = ('?');
  $deep = 100;			# warning if stack gets this deep
  $window = 10;
  $preview = 3;
  $sub = '';
  $SIG{INT} = \&DB::catch;
  # This may be enabled to debug debugger:
  #$warnLevel = 1 unless defined $warnLevel;
  #$dieLevel = 1 unless defined $dieLevel;
  #$signalLevel = 1 unless defined $signalLevel;

  $db_stop = 0;			# Compiler warning
  $db_stop = 1 << 30;
  $level = 0;			# Level of recursive debugging
  # @stack and $doret are needed in sub sub, which is called for DB::postponed.
  # Triggers bug (?) in perl is we postpone this until runtime:
  @postponed = @stack = (0);
  $doret = -2;
  $frame = 0;
}

BEGIN {$^W = $ini_warn;}	# Switch warnings back

#use Carp;			# This did break, left for debuggin

sub db_complete {
  # Specific code for b c l V m f O, &blah, $blah, @blah, %blah
  my($text, $line, $start) = @_;
  my ($itext, $search, $prefix, $pack) =
    ($text, "^\Q$ {'package'}::\E([^:]+)\$");
  
  return sort grep /^\Q$text/, (keys %sub), qw(postpone load compile), # subroutines
                               (map { /$search/ ? ($1) : () } keys %sub)
    if (substr $line, 0, $start) =~ /^\|*[blc]\s+((postpone|compile)\s+)?$/;
  return sort grep /^\Q$text/, values %INC # files
    if (substr $line, 0, $start) =~ /^\|*b\s+load\s+$/;
  return sort map {($_, db_complete($_ . "::", "V ", 2))}
    grep /^\Q$text/, map { /^(.*)::$/ ? ($1) : ()} keys %:: # top-packages
      if (substr $line, 0, $start) =~ /^\|*[Vm]\s+$/ and $text =~ /^\w*$/;
  return sort map {($_, db_complete($_ . "::", "V ", 2))}
    grep !/^main::/,
      grep /^\Q$text/, map { /^(.*)::$/ ? ($prefix . "::$1") : ()} keys %{$prefix . '::'}
				 # packages
	if (substr $line, 0, $start) =~ /^\|*[Vm]\s+$/ 
	  and $text =~ /^(.*[^:])::?(\w*)$/  and $prefix = $1;
  if ( $line =~ /^\|*f\s+(.*)/ ) { # Loaded files
    # We may want to complete to (eval 9), so $text may be wrong
    $prefix = length($1) - length($text);
    $text = $1;
    return sort 
	map {substr $_, 2 + $prefix} grep /^_<\Q$text/, (keys %main::), $0
  }
  if ((substr $text, 0, 1) eq '&') { # subroutines
    $text = substr $text, 1;
    $prefix = "&";
    return sort map "$prefix$_", 
               grep /^\Q$text/, 
                 (keys %sub),
                 (map { /$search/ ? ($1) : () } 
		    keys %sub);
  }
  if ($text =~ /^[\$@%](.*)::(.*)/) { # symbols in a package
    $pack = ($1 eq 'main' ? '' : $1) . '::';
    $prefix = (substr $text, 0, 1) . $1 . '::';
    $text = $2;
    my @out 
      = map "$prefix$_", grep /^\Q$text/, grep /^_?[a-zA-Z]/, keys %$pack ;
    if (@out == 1 and $out[0] =~ /::$/ and $out[0] ne $itext) {
      return db_complete($out[0], $line, $start);
    }
    return sort @out;
  }
  if ($text =~ /^[\$@%]/) { # symbols (in $package + packages in main)
    $pack = ($package eq 'main' ? '' : $package) . '::';
    $prefix = substr $text, 0, 1;
    $text = substr $text, 1;
    my @out = map "$prefix$_", grep /^\Q$text/, 
       (grep /^_?[a-zA-Z]/, keys %$pack), 
       ( $pack eq '::' ? () : (grep /::$/, keys %::) ) ;
    if (@out == 1 and $out[0] =~ /::$/ and $out[0] ne $itext) {
      return db_complete($out[0], $line, $start);
    }
    return sort @out;
  }
  if ((substr $line, 0, $start) =~ /^\|*O\b.*\s$/) { # Options after a space
    my @out = grep /^\Q$text/, @options;
    my $val = option_val($out[0], undef);
    my $out = '? ';
    if (not defined $val or $val =~ /[\n\r]/) {
      # Can do nothing better
    } elsif ($val =~ /\s/) {
      my $found;
      foreach $l (split //, qq/\"\'\#\|/) {
	$out = "$l$val$l ", last if (index $val, $l) == -1;
      }
    } else {
      $out = "=$val ";
    }
    # Default to value if one completion, to question if many
    $rl_attribs->{completer_terminator_character} = (@out == 1 ? $out : '? ');
    return sort @out;
  }
  return $term->filename_list($text); # filenames
}

sub end_report {
  print $OUT "Use `q' to quit or `R' to restart.  `h q' for details.\n"
}

END {
  $finished = $inhibit_exit;	# So that some keys may be disabled.
  # Do not stop in at_exit() and destructors on exit:
  $DB::single = !$exiting && !$runnonstop;
  DB::fake::at_exit() unless $exiting or $runnonstop;
}

package DB::fake;

sub at_exit {
  "Debugged program terminated.  Use `q' to quit or `R' to restart.";
}

package DB;			# Do not trace this 1; below!

1;
