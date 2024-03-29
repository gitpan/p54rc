package CPAN;
use vars qw{$META $Signal $Cwd $End $Suppress_readline};

$VERSION = '1.2401';

# $Id: CPAN.pm,v 1.139 1997/03/31 22:43:23 k Exp $

# my $version = substr q$Revision: 1.139 $, 10; # only used during development

use Carp ();
use Config ();
use Cwd ();
use DirHandle;
use Exporter ();
use ExtUtils::MakeMaker ();
use File::Basename ();
use File::Copy ();
use File::Find;
use File::Path ();
use FileHandle ();
use Safe ();
use Text::ParseWords ();
use Text::Wrap;

my $getcwd;
$getcwd  = $CPAN::Config->{'getcwd'} || 'cwd';
$Cwd = Cwd->$getcwd();

END { $End++; &cleanup; }

%CPAN::DEBUG = qw(
		  CPAN              1
		  Index             2
		  InfoObj           4
		  Author            8
		  Distribution     16
		  Bundle           32
		  Module           64
		  CacheMgr        128
		  Complete        256
		  FTP             512
		  Shell          1024
		  Eval           2048
		  Config         4096
		 );

$CPAN::DEBUG ||= 0;
$CPAN::Signal ||= 0;

package CPAN;
use vars qw($VERSION @EXPORT $AUTOLOAD $DEBUG $META $term);
use strict qw(vars);

@CPAN::ISA = qw(CPAN::Debug Exporter MM); # the MM class from
                                          # MakeMaker, gives us
                                          # catfile and catdir

$META ||= new CPAN;                 # In case we reeval ourselves we
                                    # need a ||

@EXPORT = qw( 
	     autobundle bundle expand force get
	     install make readme recompile shell test clean
	    );



#-> sub CPAN::autobundle ;
sub autobundle;
#-> sub CPAN::bundle ;
sub bundle;
#-> sub CPAN::expand ;
sub expand;
#-> sub CPAN::force ;
sub force;
#-> sub CPAN::install ;
sub install;
#-> sub CPAN::make ;
sub make;
#-> sub CPAN::shell ;
sub shell;
#-> sub CPAN::clean ;
sub clean;
#-> sub CPAN::test ;
sub test;

#-> sub CPAN::AUTOLOAD ;
sub AUTOLOAD {
    my($l) = $AUTOLOAD;
    $l =~ s/.*:://;
    my(%EXPORT);
    @EXPORT{@EXPORT} = '';
    if (exists $EXPORT{$l}){
	CPAN::Shell->$l(@_);
    } else {
	warn "CPAN doesn't know how to autoload $AUTOLOAD :-(
Nothing Done.
";
	CPAN::Shell->h;
    }
}

#-> sub CPAN::all ;
sub all {
    my($mgr,$class) = @_;
    CPAN->debug("mgr[$mgr] class[$class]") if $CPAN::DEBUG;
    CPAN::Index->reload;
    values %{ $META->{$class} };
}

# Called by shell, not in batch mode. Not clean XXX
#-> sub CPAN::checklock ;
sub checklock {
    my($self) = @_;
    my $lockfile = CPAN->catfile($CPAN::Config->{cpan_home},".lock");
    if (-f $lockfile && -M _ > 0) {
	my $fh = FileHandle->new($lockfile);
	my $other = <$fh>;
	$fh->close;
	if (defined $other && $other) {
	    chomp $other;
	    return if $$==$other; # should never happen
	    print qq{There seems to be running another CPAN process }.
		qq{($other). Trying to contact...\n};
	    if (kill 0, $other) {
		Carp::croak qq{Other job is running.\n}.
		    qq{You may want to kill it and delete the lockfile, }.
			qq{maybe. On UNIX try:\n}.
			qq{    kill $other\n}.
			    qq{    rm $lockfile\n};
	    } elsif (-w $lockfile) {
		my($ans) =
		    ExtUtils::MakeMaker::prompt
			(qq{Other job not responding. Shall I overwrite }.
			 qq{the lockfile? (Y/N)},"y");
		print("Ok, bye\n"), exit unless $ans =~ /^y/i;
	    } else {
		Carp::croak(
			    qq{Lockfile $lockfile not writeable by you. }.
			    qq{Cannot proceed.\n}.
			    qq{    On UNIX try:\n}.
			    qq{    rm $lockfile\n}.
			    qq{  and then rerun us.\n}
			   );
	    }
	}
    }
    File::Path::mkpath($CPAN::Config->{cpan_home});
    my $fh;
    unless ($fh = FileHandle->new(">$lockfile")) {
	if ($! =~ /Permission/) {
	    my $incc = $INC{'CPAN/Config.pm'};
	    my $myincc = MM->catfile($ENV{HOME},'.cpan','CPAN','MyConfig.pm');
	    print qq{

Your configuration suggests that CPAN.pm should use a working
directory of
    $CPAN::Config->{cpan_home}
Unfortunately we could not create the lock file
    $lockfile
due to permission problems.

Please make sure that the configuration variable
    \$CPAN::Config->{cpan_home}
points to a directory where you can write a .lock file. You can set
this variable in either
    $incc
or
    $myincc

};
	}
	Carp::croak "Could not open >$lockfile: $!";
    }
    print $fh $$, "\n";
    $self->{LOCK} = $lockfile;
    $fh->close;
    $SIG{'TERM'} = sub { &cleanup; die "Got SIGTERM, leaving"; };
    $SIG{'INT'} = sub {
	my $s = $Signal == 2 ? "a second" : "another";
	&cleanup, die "Got $s SIGINT" if $Signal;
	$Signal = 1;
    };
    $SIG{'__DIE__'} = \&cleanup;
    $self->debug("Signal handler set.") if $CPAN::DEBUG;
}

#-> sub CPAN::DESTROY ;
sub DESTROY {
    &cleanup; # need an eval?
}

#-> sub CPAN::exists ;
sub exists {
    my($mgr,$class,$id) = @_;
    CPAN::Index->reload;
    ### Carp::croak "exists called without class argument" unless $class;
    $id ||= "";
    exists $META->{$class}{$id};
}

#-> sub CPAN::hasFTP ;
sub hasFTP {
    my($self,$arg) = @_;
    if (defined $arg) {
	return $self->{'hasFTP'} = $arg;
    } elsif (not defined $self->{'hasFTP'}) {
	eval {require Net::FTP;};
	$self->{'hasFTP'} = $@ ? 0 : 1;
    }
    return $self->{'hasFTP'};
}

#-> sub CPAN::hasLWP ;
sub hasLWP {
    my($self,$arg) = @_;
    if (defined $arg) {
	return $self->{'hasLWP'} = $arg;
    } elsif (not defined $self->{'hasLWP'}) {
	eval {require LWP;};
	$LWP::VERSION ||= 0;
        $self->{'hasLWP'} = $LWP::VERSION >= 4.98;
    }
    return $self->{'hasLWP'};
}

#-> sub CPAN::hasMD5 ;
sub hasMD5 {
    my($self,$arg) = @_;
    if (defined $arg) {
	$self->{'hasMD5'} = $arg;
    } elsif (not defined $self->{'hasMD5'}) {
	eval {require MD5;};
	if ($@) {
	    print "MD5 security checks disabled because MD5 not installed.
  Please consider installing the MD5 module\n";
	    $self->{'hasMD5'} = 0;
	} else {
	    $self->{'hasMD5'}++;
	}
    }
    return $self->{'hasMD5'};
}

#-> sub CPAN::hasWAIT ;
sub hasWAIT {
    my($self,$arg) = @_;
    if (defined $arg) {
	$self->{'hasWAIT'} = $arg;
    } elsif (not defined $self->{'hasWAIT'}) {
	eval {require CPAN::WAIT;};
	if ($@) {
	    $self->{'hasWAIT'} = 0;
	} else {
	    $self->{'hasWAIT'} = 1;
	}
    }
    return $self->{'hasWAIT'};
}

#-> sub CPAN::instance ;
sub instance {
    my($mgr,$class,$id) = @_;
    ### CPAN::Index->reload; ### not faster: unless time - $CPAN::Index::last_time > 60;
    CPAN::Index->reload;
    ### Carp::croak "instance called without class argument" unless $class;
    $id ||= "";
    $META->{$class}{$id} ||= $class->new(ID => $id );
}

#-> sub CPAN::new ;
sub new {
    bless {}, shift;
}

#-> sub CPAN::cleanup ;
sub cleanup {
    local $SIG{__DIE__} = '';
    my $i = 0; my $ineval = 0; my $sub;
    while ((undef,undef,undef,$sub) = caller(++$i)) {
      $ineval = 1, last if $sub eq '(eval)';
    }
    return if $ineval && !$End;
    return unless defined $META->{'LOCK'};
    return unless -f $META->{'LOCK'};
    unlink $META->{'LOCK'};
    print STDERR "Lockfile removed.\n";
#    my $mess = Carp::longmess(@_);
#    die @_;
}

#-> sub CPAN::shell ;
sub shell {
    $Suppress_readline ||= ! -t STDIN;

    my $prompt = "cpan> ";
    local($^W) = 1;
    unless ($Suppress_readline) {
	require Term::ReadLine;
#	import Term::ReadLine;
	$term = new Term::ReadLine 'CPAN Monitor';
	$readline::rl_completion_function =
	    $readline::rl_completion_function = 'CPAN::Complete::complete';
    }

    no strict;
    $META->checklock();
    my $getcwd;
    $getcwd = $CPAN::Config->{'getcwd'} || 'cwd';
    my $cwd = Cwd->$getcwd();
    my $rl_avail = $Suppress_readline ? "suppressed" :
	($term->ReadLine ne "Term::ReadLine::Stub") ? "enabled" :
	    "available (get Term::ReadKey and Term::ReadLine::Perl ".
	    "or get Term::ReadLine::Gnu)";

    print qq{
cpan shell -- CPAN exploration and modules installation (v$CPAN::VERSION)
Readline support $rl_avail

} unless $CPAN::Config->{'inhibit_startup_message'} ;
    while () {
	if ($Suppress_readline) {
	    print $prompt;
	    last unless defined ($_ = <> );
	    chomp;
	} else {
#	     if (defined($CPAN::ANDK) && $CPAN::DEBUG) { # !$CPAN::ANDK++;$CPAN::DEBUG=1024
#		 my($report,$item);
#		 $report = "";
#		 for $item (qw/ReadLine IN OUT MinLine findConsole Features/) {
#		     $report .= sprintf "%-15s", $item;
#		     $report .= $term->$item() || "";
#		     $report .= "\n";
#		 }
#		 print $report;
#		CPAN->debug($report);
#	    }
	    last unless defined ($_ = $term->readline($prompt));
	}
	s/^\s//;
	next if /^$/;
	$_ = 'h' if $_ eq '?';
	if (/^\!/) {
	    s/^\!//;
	    my($eval) = $_;
	    package CPAN::Eval;
	    use vars qw($import_done);
	    CPAN->import(':DEFAULT') unless $import_done++;
	    CPAN->debug("eval[$eval]") if $CPAN::DEBUG;
	    eval($eval);
	    warn $@ if $@;
	} elsif (/^q(?:uit)?$/i) {
	    last;
	} elsif (/./) {
	    my(@line);
	    if ($] < 5.00322) { # parsewords had a bug until recently
		@line = split;
	    } else {
		eval { @line = Text::ParseWords::shellwords($_) };
		warn($@), next if $@;
	    }
	    $CPAN::META->debug("line[".join("|",@line)."]") if $CPAN::DEBUG;
	    my $command = shift @line;
	    eval { CPAN::Shell->$command(@line) };
	    warn $@ if $@;
	}
    } continue {
	&cleanup, die if $Signal;
	chdir $cwd;
	print "\n";
    }
}

package CPAN::CacheMgr;
use vars qw($Du);
@CPAN::CacheMgr::ISA = qw(CPAN::InfoObj);
use File::Find;

#-> sub CPAN::CacheMgr::as_string ;
sub as_string {
    eval { require Data::Dumper };
    if ($@) {
	return shift->SUPER::as_string;
    } else {
	return Data::Dumper::Dumper(shift);
    }
}

#-> sub CPAN::CacheMgr::cachesize ;
sub cachesize {
    shift->{DU};
}

# sub check {
#     my($self,@dirs) = @_;
#     return unless -d $self->{ID};
#     my $dir;
#     @dirs = $self->dirs unless @dirs;
#     for $dir (@dirs) {
# 	  $self->disk_usage($dir);
#     }
# }

#-> sub CPAN::CacheMgr::clean_cache ;
#=# sub clean_cache {
#=# 	my $self = shift;
#=# 	my $dir;
#=# 	while ($self->{DU} > $self->{'MAX'} and $dir = shift @{$self->{FIFO}}) {
#=# 	    $self->force_clean_cache($dir);
#=# 	}
#=# 	$self->debug("leaving clean_cache with $self->{DU}") if $CPAN::DEBUG;
#=# }

#-> sub CPAN::CacheMgr::dir ;
sub dir {
    shift->{ID};
}

#-> sub CPAN::CacheMgr::entries ;
sub entries {
    my($self,$dir) = @_;
    $self->debug("reading dir[$dir]") if $CPAN::DEBUG;
    $dir ||= $self->{ID};
    my $getcwd;
    $getcwd  = $CPAN::Config->{'getcwd'} || 'cwd';
    my($cwd) = Cwd->$getcwd();
    chdir $dir or Carp::croak("Can't chdir to $dir: $!");
    my $dh = DirHandle->new(".") or Carp::croak("Couldn't opendir $dir: $!");
    my(@entries);
    for ($dh->read) {
	next if $_ eq "." || $_ eq "..";
	if (-f $_) {
	    push @entries, $CPAN::META->catfile($dir,$_);
	} elsif (-d _) {
	    push @entries, $CPAN::META->catdir($dir,$_);
	} else {
	    print STDERR "Warning: weird direntry in $dir: $_\n";
	}
    }
    chdir $cwd or Carp::croak("Can't chdir to $cwd: $!");
    sort { -M $b <=> -M $a} @entries;
}

#-> sub CPAN::CacheMgr::disk_usage ;
sub disk_usage {
    my($self,$dir) = @_;
#    if (! defined $dir or $dir eq "") {
#	$self->debug("Cannot determine disk usage for some reason") if $CPAN::DEBUG;
#	return;
#    }
    return if $self->{SIZE}{$dir};
    local($Du) = 0;
    find(
	 sub {
	     return if -l $_;
	     $Du += -s _;
	 },
	 $dir
	);
    $self->{SIZE}{$dir} = $Du/1024/1024;
    push @{$self->{FIFO}}, $dir;
    $self->debug("measured $dir is $Du") if $CPAN::DEBUG;
    $self->{DU} += $Du/1024/1024;
    if ($self->{DU} > $self->{'MAX'} ) {
	my($toremove) = shift @{$self->{FIFO}};
	printf "...Hold on a sec... cleaning from cache (%.1f>%.1f MB): $toremove\n",
		$self->{DU}, $self->{'MAX'};
	$self->force_clean_cache($toremove);
    }
    $self->{DU};
}

#-> sub CPAN::CacheMgr::force_clean_cache ;
sub force_clean_cache {
    my($self,$dir) = @_;
    $self->debug("have to rmtree $dir, will free $self->{SIZE}{$dir}")
	if $CPAN::DEBUG;
    File::Path::rmtree($dir);
    $self->{DU} -= $self->{SIZE}{$dir};
    delete $self->{SIZE}{$dir};
}

#-> sub CPAN::CacheMgr::new ;
sub new {
    my $class = shift;
    my $time = time;
    my($debug,$t2);
    $debug = "";
    my $self = {
		ID => $CPAN::Config->{'build_dir'},
		MAX => $CPAN::Config->{'build_cache'},
		DU => 0
	       };
    File::Path::mkpath($self->{ID});
    my $dh = DirHandle->new($self->{ID});
    bless $self, $class;
    $self->debug("dir [$self->{ID}]") if $CPAN::DEBUG;
    my $e;
    for $e ($self->entries) {
	next if $e eq ".." || $e eq ".";
	$self->disk_usage($e);
    }
    $t2 = time;
    $debug .= "timing of CacheMgr->new: ".($t2 - $time);
    $time = $t2;
    CPAN->debug($debug) if $CPAN::DEBUG;
    $self;
}

package CPAN::Debug;

#-> sub CPAN::Debug::debug ;
sub debug {
    my($self,$arg) = @_;
    my($caller,$func,$line,@rest) = caller(1); # caller(0) eg
                                               # Complete, caller(1)
                                               # eg readline
    ($caller) = caller(0);
    $caller =~ s/.*:://;
#    print "caller[$caller]func[$func]line[$line]rest[@rest]\n";
#    print "CPAN::DEBUG{caller}[$CPAN::DEBUG{$caller}]CPAN::DEBUG[$CPAN::DEBUG]\n";
    if ($CPAN::DEBUG{$caller} & $CPAN::DEBUG){
	if (ref $arg) {
	    eval { require Data::Dumper };
	    if ($@) {
		print $arg->as_string;
	    } else {
		print Data::Dumper::Dumper($arg);
	    }
	} else {
	    print "Debug($caller:$func,$line,@rest): $arg\n"
	}
    }
}

package CPAN::Config;
import ExtUtils::MakeMaker 'neatvalue';
use vars qw(%can);

%can = (
  'commit' => "Commit changes to disk",
  'defaults' => "Reload defaults from disk",
  'init'   => "Interactive setting of all options",
);

#-> sub CPAN::Config::edit ;
sub edit {
    my($class,@args) = @_;
    return unless @args;
    CPAN->debug("class[$class]args[".join(" | ",@args)."]");
    my($o,$str,$func,$args,$key_exists);
    $o = shift @args;
    if($can{$o}) {
	$class->$o(@args);
	return 1;
    } else {
	if (ref($CPAN::Config->{$o}) eq ARRAY) {
	    $func = shift @args;
	    $func ||= "";
	    # Let's avoid eval, it's easier to comprehend without.
	    if ($func eq "push") {
		push @{$CPAN::Config->{$o}}, @args;
	    } elsif ($func eq "pop") {
		pop @{$CPAN::Config->{$o}};
	    } elsif ($func eq "shift") {
		shift @{$CPAN::Config->{$o}};
	    } elsif ($func eq "unshift") {
		unshift @{$CPAN::Config->{$o}}, @args;
	    } elsif ($func eq "splice") {
		splice @{$CPAN::Config->{$o}}, @args;
	    } elsif (@args) {
		$CPAN::Config->{$o} = [@args];
	    } else {
		print(
		      "  $o  ",
		      ExtUtils::MakeMaker::neatvalue($CPAN::Config->{$o}),
		      "\n"
		     );
	    }
	} else {
	    $CPAN::Config->{$o} = $args[0] if defined $args[0];
	    print "    $o    ";
	    print defined $CPAN::Config->{$o} ? $CPAN::Config->{$o} : "UNDEFINED";
	}
    }
}

#-> sub CPAN::Config::commit ;
sub commit {
    my($self,$configpm) = @_;
    unless (defined $configpm){
	$configpm ||= $INC{"CPAN/MyConfig.pm"};
	$configpm ||= $INC{"CPAN/Config.pm"};
	$configpm || Carp::confess(qq{
CPAN::Config::commit called without an argument.
Please specify a filename where to save the configuration or try
"o conf init" to have an interactive course through configing.
});
    }
    my($mode);
    if (-f $configpm) {
	$mode = (stat $configpm)[2];
	if ($mode && ! -w _) {
	    Carp::confess("$configpm is not writable");
	}
    }

    my $msg = <<EOF unless $configpm =~ /MyConfig/;

# This is CPAN.pm's systemwide configuration file.  This file provides
# defaults for users, and the values can be changed in a per-user configuration
# file. The user-config file is being looked for as ~/.cpan/CPAN/MyConfig.pm.

EOF
    $msg ||= "\n";
    my($fh) = FileHandle->new;
    open $fh, ">$configpm" or warn "Couldn't open >$configpm: $!";
    print $fh qq[$msg\$CPAN::Config = \{\n];
    foreach (sort keys %$CPAN::Config) {
	$fh->print(
		   "  '$_' => ",
		   ExtUtils::MakeMaker::neatvalue($CPAN::Config->{$_}),
		   ",\n"
		  );
    }

    print $fh "};\n1;\n__END__\n";
    close $fh;

    #$mode = 0444 | ( $mode & 0111 ? 0111 : 0 );
    #chmod $mode, $configpm;
###why was that so?    $self->defaults;
    print "commit: wrote $configpm\n";
    1;
}

*default = \&defaults;
#-> sub CPAN::Config::defaults ;
sub defaults {
    my($self) = @_;
    $self->unload;
    $self->load;
    1;
}

sub init {
    my($self) = @_;
    undef $CPAN::Config->{'inhibit_startup_message'}; # lazy trick to
                                                      # have the least
                                                      # important
                                                      # variable
                                                      # undefined
    $self->load;
    1;
}

my $dot_cpan;
#-> sub CPAN::Config::load ;
sub load {
    my($self) = shift;
    my(@miss);
    eval {require CPAN::Config;};       # We eval, because of some MakeMaker problems
    unshift @INC, $CPAN::META->catdir($ENV{HOME},".cpan") unless $dot_cpan++;
    eval {require CPAN::MyConfig;};     # where you can override system wide settings
    return unless @miss = $self->not_loaded;
    require CPAN::FirstTime;
    my($configpm,$fh,$redo);
    $redo ||= "";
    if (defined $INC{"CPAN/Config.pm"} && -w $INC{"CPAN/Config.pm"}) {
	$configpm = $INC{"CPAN/Config.pm"};
	$redo++;
    } elsif (defined $INC{"CPAN/MyConfig.pm"} && -w $INC{"CPAN/MyConfig.pm"}) {
	$configpm = $INC{"CPAN/MyConfig.pm"};
	$redo++;
    } else {
	my($path_to_cpan) = File::Basename::dirname($INC{"CPAN.pm"});
	my($configpmdir) = MM->catdir($path_to_cpan,"CPAN");
	my($configpmtest) = MM->catfile($configpmdir,"Config.pm");
	if (-d $configpmdir or File::Path::mkpath($configpmdir)) {
	    if (-w $configpmtest) {
		$configpm = $configpmtest;
	    } elsif (-w $configpmdir) {
		#_#_# following code dumped core on me with 5.003_11, a.k.
		unlink "$configpmtest.bak" if -f "$configpmtest.bak";
		rename $configpmtest, "$configpmtest.bak" if -f $configpmtest;
		my $fh = FileHandle->new;
		if ($fh->open(">$configpmtest")) {
		    $fh->print("1;\n");
		    $configpm = $configpmtest;
		} else {
		    # Should never happen
		    Carp::confess("Cannot open >$configpmtest");
		}
	    }
	}
	unless ($configpm) {
	    $configpmdir = MM->catdir($ENV{HOME},".cpan","CPAN");
	    File::Path::mkpath($configpmdir);
	    $configpmtest = MM->catfile($configpmdir,"MyConfig.pm");
	    if (-w $configpmtest) {
		$configpm = $configpmtest;
	    } elsif (-w $configpmdir) {
		#_#_# following code dumped core on me with 5.003_11, a.k.
		my $fh = FileHandle->new;
		if ($fh->open(">$configpmtest")) {
		    $fh->print("1;\n");
		    $configpm = $configpmtest;
		} else {
		    # Should never happen
		    Carp::confess("Cannot open >$configpmtest");
		}
	    } else {
		Carp::confess(qq{WARNING: CPAN.pm is unable to }.
			      qq{create a configuration file.});
	    }
	}
    }
    local($") = ", ";
    print qq{
We have to reconfigure CPAN.pm due to following uninitialized parameters:

@miss
} if $redo ;
    print qq{
$configpm initialized.
};
    sleep 2;
    CPAN::FirstTime::init($configpm);
}

#-> sub CPAN::Config::not_loaded ;
sub not_loaded {
    my(@miss);
    for (qw(
	    cpan_home keep_source_where build_dir build_cache index_expire
	    gzip tar unzip make pager makepl_arg make_arg make_install_arg
	    urllist inhibit_startup_message ftp_proxy http_proxy no_proxy
	   )) {
	push @miss, $_ unless defined $CPAN::Config->{$_};
    }
    return @miss;
}

#-> sub CPAN::Config::unload ;
sub unload {
    delete $INC{'CPAN/MyConfig.pm'};
    delete $INC{'CPAN/Config.pm'};
}

*h = \&help;
#-> sub CPAN::Config::help ;
sub help {
    print <<EOF;
Known options:
  defaults  reload default config values from disk
  commit    commit session changes to disk
  init      go through a dialog to set all parameters

You may edit key values in the follow fashion:

  o conf build_cache 15

  o conf build_dir "/foo/bar"

  o conf urllist shift

  o conf urllist unshift ftp://ftp.foo.bar/

EOF
    undef; #don't reprint CPAN::Config
}

#-> sub CPAN::Config::complete ;
sub complete {
    my($word,$line,$pos) = @_;
    $word ||= "";
    my(@o_conf) = (keys %CPAN::Config::can, keys %$CPAN::Config);
    return grep /^\Q$word\E/, @o_conf;
}

package CPAN::Shell;
use vars qw($AUTOLOAD $redef @ISA);
@CPAN::Shell::ISA = qw(CPAN::Debug);
if ($CPAN::META->hasWAIT) {
    unshift @ISA, "CPAN::WAIT";
}
# private function ro re-eval this module (handy during development)
#-> sub CPAN::Shell::AUTOLOAD ;
sub AUTOLOAD {
    my($autoload) = $AUTOLOAD;
    $autoload =~ s/.*:://;
    if ($autoload =~ /^w/) {
	if ($CPAN::META->hasWAIT) {
	    CPAN::WAIT->wh;
	    return;
	} else {
	    print STDERR qq{
Commands starting with "w" require CPAN::WAIT to be installed.
Please consider installing CPAN::WAIT to use the fulltext index.
Type "install CPAN::WAIT" and restart CPAN.pm.
}
	}
    } else {
	warn "CPAN::Shell doesn't know how to autoload $autoload :-(
Nothing Done.
";
    }
    CPAN::Shell->h;
}

#-> sub CPAN::Shell::h ;
sub h {
    my($class,$about) = @_;
    if (defined $about) {
	print "Detailed help not yet implemented\n";
    } else {
	print q{
command   arguments       description
a         string                  authors
b         or              display bundles
d         /regex/         info    distributions
m         or              about   modules
i         none                    anything of above

r          as             reinstall recommendations
u          above          uninstalled distributions
See manpage for autobundle, recompile, force, look, etc.

make                      make
test      modules,        make test (implies make)
install   dists, bundles, make install (implies test)
clean     "r" or "u"      make clean
readme                    display the README file

reload    index|cpan    load most recent indices/CPAN.pm
h or ?                  display this menu
o         various       set and query options
!         perl-code     eval a perl command
q                       quit the shell subroutine
};
    }
}

#-> sub CPAN::Shell::a ;
sub a { print shift->format_result('Author',@_);}
#-> sub CPAN::Shell::b ;
sub b {
    my($self,@which) = @_;
    CPAN->debug("which[@which]") if $CPAN::DEBUG;
    my($incdir,$bdir,$dh); 
    foreach $incdir ($CPAN::Config->{'cpan_home'},@INC) {
	$bdir = $CPAN::META->catdir($incdir,"Bundle");
	if ($dh = DirHandle->new($bdir)) { # may fail
	    my($entry);
	    for $entry ($dh->read) {
		next if -d $CPAN::META->catdir($bdir,$entry);
		next unless $entry =~ s/\.pm$//;
		$CPAN::META->instance('CPAN::Bundle',"Bundle::$entry");
	    }
	}
    }
    print $self->format_result('Bundle',@which);
}
#-> sub CPAN::Shell::d ;
sub d { print shift->format_result('Distribution',@_);}
#-> sub CPAN::Shell::m ;
sub m { print shift->format_result('Module',@_);}

#-> sub CPAN::Shell::i ;
sub i {
    my($self) = shift;
    my(@args) = @_;
    my(@type,$type,@m);
    @type = qw/Author Bundle Distribution Module/;
    @args = '/./' unless @args;
    my(@result);
    for $type (@type) {
	push @result, $self->expand($type,@args);
    }
    my $result =  @result == 1 ?
	$result[0]->as_string :
	    join "", map {$_->as_glimpse} @result;
    $result ||= "No objects found of any type for argument @args\n";
    print $result;
}

#-> sub CPAN::Shell::o ;
sub o {
    my($self,$o_type,@o_what) = @_;
    $o_type ||= "";
    CPAN->debug("o_type[$o_type] o_what[".join(" | ",@o_what)."]\n");
    if ($o_type eq 'conf') {
	shift @o_what if @o_what && $o_what[0] eq 'help';
	if (!@o_what) {
	    my($k,$v);
	    print "CPAN::Config options:\n";
	    for $k (sort keys %CPAN::Config::can) {
		$v = $CPAN::Config::can{$k};
		printf "    %-18s %s\n", $k, $v;
	    }
	    print "\n";
	    for $k (sort keys %$CPAN::Config) {
		$v = $CPAN::Config->{$k};
		if (ref $v) {
		    printf "    %-18s\n", $k;
		    print map {"\t$_\n"} @{$v};
		} else {
		    printf "    %-18s %s\n", $k, $v;
		}
	    }
	    print "\n";
	} elsif (!CPAN::Config->edit(@o_what)) {
	    print qq[Type 'o conf' to view configuration edit options\n\n];
	}
    } elsif ($o_type eq 'debug') {
	my(%valid);
	@o_what = () if defined $o_what[0] && $o_what[0] =~ /help/i;
	if (@o_what) {
	    while (@o_what) {
		my($what) = shift @o_what;
		if ( exists $CPAN::DEBUG{$what} ) {
		    $CPAN::DEBUG |= $CPAN::DEBUG{$what};
		} elsif ($what =~ /^\d/) {
		    $CPAN::DEBUG = $what;
		} elsif (lc $what eq 'all') {
		    my($max) = 0;
		    for (values %CPAN::DEBUG) {
			$max += $_;
		    }
		    $CPAN::DEBUG = $max;
		} else {
		    my($known) = 0;
		    for (keys %CPAN::DEBUG) {
			next unless lc($_) eq lc($what);
			$CPAN::DEBUG |= $CPAN::DEBUG{$_};
			$known = 1;
		    }
		    print "unknown argument [$what]\n" unless $known;
		}
	    }
	} else {
	    print "Valid options for debug are ".
		join(", ",sort(keys %CPAN::DEBUG), 'all').
		    qq{ or a number. Completion works on the options. }.
			qq{Case is ignored.\n\n};
	}
	if ($CPAN::DEBUG) {
	    print "Options set for debugging:\n";
	    my($k,$v);
	    for $k (sort {$CPAN::DEBUG{$a} <=> $CPAN::DEBUG{$b}} keys %CPAN::DEBUG) {
		$v = $CPAN::DEBUG{$k};
		printf "    %-14s(%s)\n", $k, $v if $v & $CPAN::DEBUG;
	    }
	} else {
	    print "Debugging turned off completely.\n";
	}
    } else {
	print qq{
Known options:
  conf    set or get configuration variables
  debug   set or get debugging options
};
    }
}

#-> sub CPAN::Shell::reload ;
sub reload {
    my($self,$command,@arg) = @_;
    $command ||= "";
    $self->debug("self[$self]command[$command]arg[@arg]") if $CPAN::DEBUG;
    if ($command =~ /cpan/i) {
	CPAN->debug("reloading the whole CPAN.pm") if $CPAN::DEBUG;
	my $fh = FileHandle->new($INC{'CPAN.pm'});
	local($/);
	undef $/;
	$redef = 0;
	local($SIG{__WARN__})
	    = sub {
		if ( $_[0] =~ /Subroutine \w+ redefined/ ) {
		    ++$redef;
		    local($|) = 1;
		    print ".";
		    return;
		}
		warn @_;
	    };
	eval <$fh>;
	warn $@ if $@;
	print "\n$redef subroutines redefined\n";
    } elsif ($command =~ /index/) {
	CPAN::Index->force_reload;
    } else {
	print qq{cpan     re-evals the CPAN.pm file\n};
	print qq{index    re-reads the index files\n};
    }
}

#-> sub CPAN::Shell::_binary_extensions ;
sub _binary_extensions {
    my($self) = shift @_;
    my(@result,$module,%seen,%need,$headerdone);
    for $module ($self->expand('Module','/./')) {
	my $file  = $module->cpan_file;
	next if $file eq "N/A";
	next if $file =~ /^Contact Author/;
	next if $file =~ /perl5[._-]\d{3}(?:[\d_]+)?\.tar[._-]gz$/;
	next unless $module->xs_file;
	local($|) = 1;
	print ".";
	push @result, $module;
    }
#    print join " | ", @result;
    print "\n";
    return @result;
}

#-> sub CPAN::Shell::recompile ;
sub recompile {
    my($self) = shift @_;
    my($module,@module,$cpan_file,%dist);
    @module = $self->_binary_extensions();
    for $module (@module){  # we force now and compile later, so we don't do it twice
	$cpan_file = $module->cpan_file;
	my $pack = $CPAN::META->instance('CPAN::Distribution',$cpan_file);
	$pack->force;
	$dist{$cpan_file}++;
    }
    for $cpan_file (sort keys %dist) {
	print "  CPAN: Recompiling $cpan_file\n\n";
	my $pack = $CPAN::META->instance('CPAN::Distribution',$cpan_file);
	$pack->install;
	$CPAN::Signal = 0; # it's tempting to reset Signal, so we can
                           # stop a package from recompiling,
                           # e.g. IO-1.12 when we have perl5.003_10
    }
}

#-> sub CPAN::Shell::_u_r_common ;
sub _u_r_common {
    my($self) = shift @_;
    my($what) = shift @_;
    CPAN->debug("self[$self] what[$what] args[@_]") if $CPAN::DEBUG;
    Carp::croak "Usage: \$obj->_u_r_common($what)" unless defined $what;
    Carp::croak "Usage: \$obj->_u_r_common(a|r|u)" unless $what =~ /^[aru]$/;
    my(@args) = @_;
    @args = '/./' unless @args;
    my(@result,$module,%seen,%need,$headerdone,$version_zeroes);
    $version_zeroes = 0;
    my $sprintf = "%-25s %9s %9s  %s\n";
    for $module ($self->expand('Module',@args)) {
	my $file  = $module->cpan_file;
	next unless defined $file; # ??
	my($latest) = $module->cpan_version || 0;
	my($inst_file) = $module->inst_file;
	my($have);
	if ($inst_file){
	    if ($what eq "a") {
		$have = $module->inst_version;
	    } elsif ($what eq "r") {
		$have = $module->inst_version;
		local($^W) = 0;
		$version_zeroes++ unless $have;
		next if $have >= $latest;
	    } elsif ($what eq "u") {
		next;
	    }
	} else {
	    if ($what eq "a") {
		next;
	    } elsif ($what eq "r") {
		next;
	    } elsif ($what eq "u") {
		$have = "-";
	    }
	}
	return if $CPAN::Signal; # this is sometimes lengthy
	$seen{$file} ||= 0;
	if ($what eq "a") {
	    push @result, sprintf "%s %s\n", $module->id, $have;
	} elsif ($what eq "r") {
	    push @result, $module->id;
	    next if $seen{$file}++;
	} elsif ($what eq "u") {
	    push @result, $module->id;
	    next if $seen{$file}++;
	    next if $file =~ /^Contact/;
	}
	unless ($headerdone++){
	    print "\n";
	    printf(
		   $sprintf,
		   "Package namespace",
		   "installed",
		   "latest",
		   "in CPAN file"
		   );
	}
	$latest = substr($latest,0,8) if length($latest) > 8;
	$have = substr($have,0,8) if length($have) > 8;
	printf $sprintf, $module->id, $have, $latest, $file;
	$need{$module->id}++;
    }
    unless (%need) {
	if ($what eq "u") {
	    print "No modules found for @args\n";
	} elsif ($what eq "r") {
	    print "All modules are up to date for @args\n";
	}
    }
    if ($what eq "r" && $version_zeroes) {
	my $s = $version_zeroes > 1 ? "s have" : " has";
	print qq{$version_zeroes installed module$s no version number to compare\n};
    }
    @result;
}

#-> sub CPAN::Shell::r ;
sub r {
    shift->_u_r_common("r",@_);
}

#-> sub CPAN::Shell::u ;
sub u {
    shift->_u_r_common("u",@_);
}

#-> sub CPAN::Shell::autobundle ;
sub autobundle {
    my($self) = shift;
    my(@bundle) = $self->_u_r_common("a",@_);
    my($todir) = $CPAN::META->catdir($CPAN::Config->{'cpan_home'},"Bundle");
    File::Path::mkpath($todir);
    unless (-d $todir) {
	print "Couldn't mkdir $todir for some reason\n";
	return;
    }
    my($y,$m,$d) =  (localtime)[5,4,3];
    $y+=1900;
    $m++;
    my($c) = 0;
    my($me) = sprintf "Snapshot_%04d_%02d_%02d_%02d", $y, $m, $d, $c;
    my($to) = $CPAN::META->catfile($todir,"$me.pm");
    while (-f $to) {
	$me = sprintf "Snapshot_%04d_%02d_%02d_%02d", $y, $m, $d, ++$c;
	$to = $CPAN::META->catfile($todir,"$me.pm");
    }
    my($fh) = FileHandle->new(">$to") or Carp::croak "Can't open >$to: $!";
    $fh->print(
	       "package Bundle::$me;\n\n",
	       "\$VERSION = '0.01';\n\n",
	       "1;\n\n",
	       "__END__\n\n",
	       "=head1 NAME\n\n",
	       "Bundle::$me - Snapshot of installation on ",
	       $Config::Config{'myhostname'},
	       " on ",
	       scalar(localtime),
	       "\n\n=head1 SYNOPSIS\n\n",
	       "perl -MCPAN -e 'install Bundle::$me'\n\n",
	       "=head1 CONTENTS\n\n",
	       join("\n", @bundle),
	       "\n\n=head1 CONFIGURATION\n\n",
	       Config->myconfig,
	       "\n\n=head1 AUTHOR\n\n",
	       "This Bundle has been generated automatically ",
	       "by the autobundle routine in CPAN.pm.\n",
	      );
    $fh->close;
    print "\nWrote bundle file
    $to\n\n";
}

#-> sub CPAN::Shell::expand ;
sub expand {
    shift;
    my($type,@args) = @_;
    my($arg,@m);
    for $arg (@args) {
	my $regex;
	if ($arg =~ m|^/(.*)/$|) {
	    $regex = $1;
	}
	my $class = "CPAN::$type";
	my $obj;
	if (defined $regex) {
	    for $obj ( sort {$a->id cmp $b->id} $CPAN::META->all($class)) {
		push @m, $obj
		    if
			$obj->id =~ /$regex/i
			    or
			(
			 (
			  $] < 5.00303 ### provide sort of compatibility with 5.003
			  ||
			  $obj->can('name')
			 )
			 &&
			 $obj->name  =~ /$regex/i
			);
	    }
	} else {
	    my($xarg) = $arg;
	    if ( $type eq 'Bundle' ) {
		$xarg =~ s/^(Bundle::)?(.*)/Bundle::$2/;
	    }
	    if ($CPAN::META->exists($class,$xarg)) {
		$obj = $CPAN::META->instance($class,$xarg);
	    } elsif ($CPAN::META->exists($class,$arg)) {
		$obj = $CPAN::META->instance($class,$arg);
	    } else {
		next;
	    }
	    push @m, $obj;
	}
    }
    return wantarray ? @m : $m[0];
}

#-> sub CPAN::Shell::format_result ;
sub format_result {
    my($self) = shift;
    my($type,@args) = @_;
    @args = '/./' unless @args;
    my(@result) = $self->expand($type,@args);
    my $result =  @result == 1 ?
	$result[0]->as_string :
	    join "", map {$_->as_glimpse} @result;
    $result ||= "No objects of type $type found for argument @args\n";
    $result;
}

#-> sub CPAN::Shell::rematein ;
sub rematein {
    shift;
    my($meth,@some) = @_;
    my $pragma = "";
    if ($meth eq 'force') {
	$pragma = $meth;
	$meth = shift @some;
    }
    CPAN->debug("pragma[$pragma]meth[$meth] some[@some]") if $CPAN::DEBUG;
    my($s,@s);
    foreach $s (@some) {
	my $obj;
	if (ref $s) {
	    $obj = $s;
	} elsif ($s =~ m|/|) { # looks like a file
	    $obj = $CPAN::META->instance('CPAN::Distribution',$s);
	} elsif ($s =~ m|^Bundle::|) {
	    $obj = $CPAN::META->instance('CPAN::Bundle',$s);
	} else {
	    $obj = $CPAN::META->instance('CPAN::Module',$s)
		if $CPAN::META->exists('CPAN::Module',$s);
	}
	if (ref $obj) {
	    CPAN->debug(
			qq{pragma[$pragma] meth[$meth] obj[$obj] as_string\[}.
			$obj->as_string.
			qq{\]}
		       ) if $CPAN::DEBUG;
	    $obj->$pragma()
		if
		    $pragma
			&&
		    ($] < 5.00303 || $obj->can($pragma)); ### compatibility with 5.003
	    $obj->$meth();
	} elsif ($CPAN::META->exists('CPAN::Author',$s)) {
	    $obj = $CPAN::META->instance('CPAN::Author',$s);
	    print "Don't be silly, you can't $meth ", $obj->fullname, " ;-)\n";
	} else {
	    print qq{Warning: Cannot $meth $s, don\'t know what it is.
Try the command

    i /$s/

to find objects with similar identifiers.
};
	}
    }
}

#-> sub CPAN::Shell::force ;
sub force   { shift->rematein('force',@_); }
#-> sub CPAN::Shell::get ;
sub get     { shift->rematein('get',@_); }
#-> sub CPAN::Shell::readme ;
sub readme  { shift->rematein('readme',@_); }
#-> sub CPAN::Shell::make ;
sub make    { shift->rematein('make',@_); }
#-> sub CPAN::Shell::test ;
sub test    { shift->rematein('test',@_); }
#-> sub CPAN::Shell::install ;
sub install { shift->rematein('install',@_); }
#-> sub CPAN::Shell::clean ;
sub clean   { shift->rematein('clean',@_); }
#-> sub CPAN::Shell::look ;
sub look   { shift->rematein('look',@_); }

package CPAN::FTP;
use vars qw($Ua);
@CPAN::FTP::ISA = qw(CPAN::Debug);

#-> sub CPAN::FTP::ftp_get ;
sub ftp_get {
    my($class,$host,$dir,$file,$target) = @_;
    $class->debug(
		       qq[Going to fetch file [$file] from dir [$dir]
	on host [$host] as local [$target]\n]
		      ) if $CPAN::DEBUG;
    my $ftp = Net::FTP->new($host);
    return 0 unless defined $ftp;
    $ftp->debug(1) if $CPAN::DEBUG{'FTP'} & $CPAN::DEBUG;
    $class->debug(qq[Going to ->login("anonymous","$Config::Config{'cf_email'}")\n]);
    unless ( $ftp->login("anonymous",$Config::Config{'cf_email'}) ){
	warn "Couldn't login on $host";
	return;
    }
    # print qq[Going to ->cwd("$dir")\n];
    unless ( $ftp->cwd($dir) ){
	warn "Couldn't cwd $dir";
	return;
    }
    $ftp->binary;
    $class->debug(qq[Going to ->get("$file","$target")\n]) if $CPAN::DEBUG;
    unless ( $ftp->get($file,$target) ){
	warn "Couldn't fetch $file from $host\n";
	return;
    }
    $ftp->quit; # it's ok if this fails
    return 1;
}

#-> sub CPAN::FTP::localize ;
sub localize {
    my($self,$file,$aslocal,$force) = @_;
    $force ||= 0;
    Carp::croak "Usage: ->localize(cpan_file,as_local_file[,$force])"
	unless defined $aslocal;
    $self->debug("file [$file] aslocal [$aslocal]") if $CPAN::DEBUG;

    return $aslocal if -f $aslocal && -r _ && ! $force;
    rename $aslocal, "$aslocal.bak" if -f $aslocal;

    my($aslocal_dir) = File::Basename::dirname($aslocal);
    File::Path::mkpath($aslocal_dir);
    print STDERR qq{Warning: You are not allowed to write into }.
	qq{directory "$aslocal_dir".
    I\'ll continue, but if you face any problems, they may be due
    to insufficient permissions.\n} unless -w $aslocal_dir;

    # Inheritance is not easier to manage than a few if/else branches
    if ($CPAN::META->hasLWP) {
	require LWP::UserAgent;
 	unless ($Ua) {
	    $Ua = new LWP::UserAgent;
	    my($var);
	    $Ua->proxy('ftp',  $var)
		if $var = $CPAN::Config->{'ftp_proxy'} || $ENV{'ftp_proxy'};
	    $Ua->proxy('http', $var)
		if $var = $CPAN::Config->{'http_proxy'} || $ENV{'http_proxy'};
	    $Ua->no_proxy($var)
		if $var = $CPAN::Config->{'no_proxy'} || $ENV{'no_proxy'};
	}
    }

    # Try the list of urls for each single object. We keep a record
    # where we did get a file from
    my($i);
    for $i (0..$#{$CPAN::Config->{urllist}}) {
	my $url = $CPAN::Config->{urllist}[$i];
	$url .= "/" unless substr($url,-1) eq "/";
	$url .= $file;
	$self->debug("localizing[$url]") if $CPAN::DEBUG;
	if ($url =~ /^file:/) {
	    my $l;
	    if ($CPAN::META->hasLWP) {
		require URI::URL;
		my $u = new URI::URL $url;
		$l = $u->path;
	    } else { # works only on Unix, is poorly constructed, but
                     # hopefully better than nothing. 
		     # RFC 1738 says fileurl BNF is
		     # fileurl = "file://" [ host | "localhost" ] "/" fpath
		     # Thanks to "Mark D. Baushke" <mdb@cisco.com> for the code
		($l = $url) =~ s,^file://[^/]+,,; # discard the host part
		$l =~ s/^file://;	# assume they meant file://localhost
	    }
	    return $l if -f $l && -r _;
	    # Maybe mirror has compressed it?
	    if (-f "$l.gz") {
		$self->debug("found compressed $l.gz") if $CPAN::DEBUG;
		system("$CPAN::Config->{gzip} -dc $l.gz > $aslocal");
		return $aslocal if -f $aslocal;
	    }
	}

	if ($CPAN::META->hasLWP) {
	    print "Fetching $url with LWP\n";
	    my $res = $Ua->mirror($url, $aslocal);
	    if ($res->is_success) {
		return $aslocal;
	    }
	}
	if ($url =~ m|^ftp://(.*?)/(.*)/(.*)|) {
	    # that's the nice and easy way thanks to Graham
	    my($host,$dir,$getfile) = ($1,$2,$3);
	    if ($CPAN::META->hasFTP) {
		$dir =~ s|/+|/|g;
		$self->debug("Going to fetch file [$getfile]
  from dir [$dir]
  on host  [$host]
  as local [$aslocal]") if $CPAN::DEBUG;
		CPAN::FTP->ftp_get($host,$dir,$getfile,$aslocal) && return $aslocal;
		warn "Net::FTP failed for some reason\n";
	    } else {
		warn qq{
  Please, install Net::FTP as soon as possible. Just type
    install Net::FTP
  Thank you.

}
	    }
	}

	# Came back if Net::FTP couldn't establish connection (or failed otherwise)
	# Maybe they are behind a firewall, but they gave us
	# a socksified (or other) ftp program...

	my($funkyftp);
	# does ncftp handle http?
	for $funkyftp ($CPAN::Config->{'lynx'},$CPAN::Config->{'ncftp'}) {
	    next unless defined $funkyftp;
	    next unless -x $funkyftp;
	    my($want_compressed);
	    print(
		  qq{
Trying with $funkyftp to get
  $url
});
	    $want_compressed = $aslocal =~ s/\.gz//;
	    my($source_switch) = "";
	    $source_switch = "-source" if $funkyftp =~ /\blynx$/;
	    my($system) = "$funkyftp $source_switch '$url' > $aslocal";
	    my($wstatus);
	    if (($wstatus = system($system)) == 0) {
		if ($want_compressed) {
		    $system = "$CPAN::Config->{'gzip'} -dt $aslocal";
		    if (system($system) == 0) {
			rename $aslocal, "$aslocal.gz";
		    } else {
			$system = "$CPAN::Config->{'gzip'} $aslocal";
			system($system);
		    }
		    return "$aslocal.gz";
		} else {
		    $system = "$CPAN::Config->{'gzip'} -dt $aslocal";
		    if (system($system) == 0) {
			$system = "$CPAN::Config->{'gzip'} -d $aslocal";
			system($system);
		    } else {
			# should be fine, eh?
		    }
		    return $aslocal;
		}
	    } else {
		my $estatus = $wstatus >> 8;
		print qq{
System call "$system"
returned status $estatus (wstat $wstatus)
};
	    }
	}

	if ($url =~ m|^ftp://(.*?)/(.*)/(.*)|) {
	    my($host,$dir,$getfile) = ($1,$2,$3);
	    my($netrcfile,$fh);
	    if (-x $CPAN::Config->{'ftp'}) {
		my $timestamp = 0;
		my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,
		   $ctime,$blksize,$blocks) = stat($aslocal);
		$timestamp = $mtime ||= 0;

		my($netrc) = CPAN::FTP::netrc->new;
		my($verbose) = $CPAN::DEBUG{'FTP'} & $CPAN::DEBUG ? " -v" : "";

		my $targetfile = File::Basename::basename($aslocal);
		my(@dialog);
		push(
		     @dialog,
		     "lcd $aslocal_dir",
		     "cd /",
		     map("cd $_", split "/", $dir), # RFC 1738
		     "bin",
		     "get $getfile $targetfile",
		     "quit"
		    );
		if (! $netrc->netrc) {
		    CPAN->debug("No ~/.netrc file found") if $CPAN::DEBUG;
		} elsif ($netrc->hasdefault || $netrc->contains($host)) {
		    CPAN->debug(
				sprint(
				       "hasdef[%d]cont($host)[%d]",
				       $netrc->hasdefault,
				       $netrc->contains($host)
				      )
			       ) if $CPAN::DEBUG;
		    if ($netrc->protected) {
			print(
			      qq{
  Trying with external ftp to get
    $url
  As this requires some features that are not thoroughly tested, we\'re
  not sure, that we get it right....

}
			     );
			my $fh = FileHandle->new;
			$fh->open("|$CPAN::Config->{'ftp'}$verbose $host")
			    or die "Couldn't open ftp: $!";
			# pilot is blind now
			CPAN->debug("dialog [".(join "|",@dialog)."]")
			    if $CPAN::DEBUG;
			foreach (@dialog) { $fh->print("$_\n") }
			$fh->close;		# Wait for process to complete
			my $wstatus = $?;
			my $estatus = $wstatus >> 8;
			print qq{
Subprocess "|$CPAN::Config->{'ftp'}$verbose $host"
  returned status $estatus (wstat $wstatus)
} if $wstatus;
			($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
			 $atime,$mtime,$ctime,$blksize,$blocks) = stat($aslocal);
			$mtime ||= 0;
			if ($mtime > $timestamp) {
			    print "GOT $aslocal\n";
			    return $aslocal;
			} else {
			    print "Hmm... Still failed!\n";
			}
		    } else {
			warn "Your $netrcfile is not correctly protected.\n";
		    }
		} else {
		    warn "Your ~/.netrc neither contains $host
  nor does it have a default entry\n";
		}

		# OK, they don't have a valid ~/.netrc. Use 'ftp -n' then and
		# login manually to host, using e-mail as password.
		print qq{Issuing "$CPAN::Config->{'ftp'}$verbose -n"\n};
		unshift(
			@dialog,
			"open $host",
			"user anonymous $Config::Config{'cf_email'}"
		       );
		CPAN->debug("dialog [".(join "|",@dialog)."]") if $CPAN::DEBUG;
		$fh = FileHandle->new;
		$fh->open("|$CPAN::Config->{'ftp'}$verbose -n") or
		    die "Cannot fork: $!\n";
		foreach (@dialog) { $fh->print("$_\n") }
		$fh->close;
		my $wstatus = $?;
		my $estatus = $wstatus >> 8;
		print qq{
Subprocess "|$CPAN::Config->{'ftp'}$verbose -n"
  returned status $estatus (wstat $wstatus)
} if $wstatus;
		($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
		   $atime,$mtime,$ctime,$blksize,$blocks) = stat($aslocal);
		$mtime ||= 0;
		if ($mtime > $timestamp) {
		    print "GOT $aslocal\n";
		    return $aslocal;
		} else {
		    print "Bad luck... Still failed!\n";
		}
	    }
	    sleep 2;
	}

	print "Can't access URL $url.\n\n";
	my(@mess,$mess);
	push @mess, "LWP" unless CPAN->hasLWP;
	push @mess, "Net::FTP" unless CPAN->hasFTP;
	my($ext);
	for $ext (qw/lynx ncftp ftp/) {
	    $CPAN::Config->{$ext} ||= "";
	    push @mess, "an external $ext" unless -x $CPAN::Config->{$ext};
	}
	$mess = qq{Either get }.
	    join(" or ",@mess).
	    qq{ or check, if the URL found in your configuration file, }.
	    $CPAN::Config->{urllist}[$i].
	    qq{, is valid.};
	print Text::Wrap::wrap("","",$mess), "\n";
    }
    print "Cannot fetch $file\n";
    if (-f "$aslocal.bak") {
	rename "$aslocal.bak", $aslocal;
	print "Trying to get away with old file:\n";
	print $self->ls($aslocal);
	return $aslocal;
    }
    return;
}

# find2perl needs modularization, too, all the following is stolen
# from there
sub ls {
    my($self,$name) = @_;
    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$sizemm,
     $atime,$mtime,$ctime,$blksize,$blocks) = lstat($name);

    my($perms,%user,%group);
    my $pname = $name;

    if (defined $blocks) {
	$blocks = int(($blocks + 1) / 2);
    }
    else {
	$blocks = int(($sizemm + 1023) / 1024);
    }

    if    (-f _) { $perms = '-'; }
    elsif (-d _) { $perms = 'd'; }
    elsif (-c _) { $perms = 'c'; $sizemm = &sizemm; }
    elsif (-b _) { $perms = 'b'; $sizemm = &sizemm; }
    elsif (-p _) { $perms = 'p'; }
    elsif (-S _) { $perms = 's'; }
    else         { $perms = 'l'; $pname .= ' -> ' . readlink($_); }

    my(@rwx) = ('---','--x','-w-','-wx','r--','r-x','rw-','rwx');
    my(@moname) = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my $tmpmode = $mode;
    my $tmp = $rwx[$tmpmode & 7];
    $tmpmode >>= 3;
    $tmp = $rwx[$tmpmode & 7] . $tmp;
    $tmpmode >>= 3;
    $tmp = $rwx[$tmpmode & 7] . $tmp;
    substr($tmp,2,1) =~ tr/-x/Ss/ if -u _;
    substr($tmp,5,1) =~ tr/-x/Ss/ if -g _;
    substr($tmp,8,1) =~ tr/-x/Tt/ if -k _;
    $perms .= $tmp;

    my $user = $user{$uid} || $uid;   # too lazy to implement lookup
    my $group = $group{$gid} || $gid;

    my($sec,$min,$hour,$mday,$mon,$year) = localtime($mtime);
    my($timeyear);
    my($moname) = $moname[$mon];
    if (-M _ > 365.25 / 2) {
	$timeyear = $year + 1900;
    }
    else {
	$timeyear = sprintf("%02d:%02d", $hour, $min);
    }

    sprintf "%5lu %4ld %-10s %2d %-8s %-8s %8s %s %2d %5s %s\n",
	    $ino,
		 $blocks,
		      $perms,
			    $nlink,
				$user,
				     $group,
					  $sizemm,
					      $moname,
						 $mday,
						     $timeyear,
							 $pname;
}

package CPAN::FTP::netrc;

sub new {
    my($class) = @_;
    my $file = MM->catfile($ENV{HOME},".netrc");

    my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
       $atime,$mtime,$ctime,$blksize,$blocks)
	= stat($file);
    $mode ||= 0;
    my $protected = 0;

    my($fh,@machines,$hasdefault);
    $hasdefault = 0;
    $fh = FileHandle->new or die "Could not create a filehandle";

    if($fh->open($file)){
	$protected = ($mode & 077) == 0;
	local($/) = "";
      NETRC: while (<$fh>) {
	    my(@tokens) = split " ", $_;
	  TOKEN: while (@tokens) {
		my($t) = shift @tokens;
		if ($t eq "default"){
		    $hasdefault++;
		    # warn "saw a default entry before tokens[@tokens]";
		    last NETRC;
		}
		last TOKEN if $t eq "macdef";
		if ($t eq "machine") {
		    push @machines, shift @tokens;
		}
	    }
	}
    } else {
	$file = $hasdefault = $protected = "";
    }

    bless {
	   'mach' => [@machines],
	   'netrc' => $file,
	   'hasdefault' => $hasdefault,
	   'protected' => $protected,
	  }, $class;
}

sub hasdefault { shift->{'hasdefault'} }
sub netrc      { shift->{'netrc'}      }
sub protected  { shift->{'protected'}  }
sub contains {
    my($self,$mach) = @_;
    for ( @{$self->{'mach'}} ) {
	return 1 if $_ eq $mach;
    }
    return 0;
}

package CPAN::Complete;
@CPAN::Complete::ISA = qw(CPAN::Debug);

#-> sub CPAN::Complete::complete ;
sub complete {
    my($word,$line,$pos) = @_;
    $word ||= "";
    $line ||= "";
    $pos ||= 0;
    CPAN->debug("word [$word] line[$line] pos[$pos]") if $CPAN::DEBUG;
    $line =~ s/^\s*//;
    if ($line =~ s/^(force\s*)//) {
	$pos -= length($1);
    }
    my @return;
    if ($pos == 0) {
	@return = grep(
		       /^$word/,
		       sort qw(
			       ! a b d h i m o q r u autobundle clean
			       make test install force reload look
			      )
		      );
    } elsif ( $line !~ /^[\!abdhimorutl]/ ) {
	@return = ();
    } elsif ($line =~ /^a\s/) {
	@return = completex('CPAN::Author',$word);
    } elsif ($line =~ /^b\s/) {
	@return = completex('CPAN::Bundle',$word);
    } elsif ($line =~ /^d\s/) {
	@return = completex('CPAN::Distribution',$word);
    } elsif ($line =~ /^([mru]|make|clean|test|install|readme|look)\s/ ) {
	@return = (completex('CPAN::Module',$word),completex('CPAN::Bundle',$word));
    } elsif ($line =~ /^i\s/) {
	@return = complete_any($word);
    } elsif ($line =~ /^reload\s/) {
	@return = complete_reload($word,$line,$pos);
    } elsif ($line =~ /^o\s/) {
	@return = complete_option($word,$line,$pos);
    } else {
	@return = ();
    }
    return @return;
}

#-> sub CPAN::Complete::completex ;
sub completex {
    my($class, $word) = @_;
    grep /^\Q$word\E/, map { $_->id } $CPAN::META->all($class);
}

#-> sub CPAN::Complete::complete_any ;
sub complete_any {
    my($word) = shift;
    return (
	    completex('CPAN::Author',$word),
	    completex('CPAN::Bundle',$word),
	    completex('CPAN::Distribution',$word),
	    completex('CPAN::Module',$word),
	   );
}

#-> sub CPAN::Complete::complete_reload ;
sub complete_reload {
    my($word,$line,$pos) = @_;
    $word ||= "";
    my(@words) = split " ", $line;
    CPAN->debug("word[$word] line[$line] pos[$pos]") if $CPAN::DEBUG;
    my(@ok) = qw(cpan index);
    return @ok if @words == 1;
    return grep /^\Q$word\E/, @ok if @words == 2 && $word;
}

#-> sub CPAN::Complete::complete_option ;
sub complete_option {
    my($word,$line,$pos) = @_;
    $word ||= "";
    my(@words) = split " ", $line;
    CPAN->debug("word[$word] line[$line] pos[$pos]") if $CPAN::DEBUG;
    my(@ok) = qw(conf debug);
    return @ok if @words == 1;
    return grep /^\Q$word\E/, @ok if @words == 2 && $word;
    if (0) {
    } elsif ($words[1] eq 'index') {
	return ();
    } elsif ($words[1] eq 'conf') {
	return CPAN::Config::complete(@_);
    } elsif ($words[1] eq 'debug') {
	return sort grep /^\Q$word\E/, sort keys %CPAN::DEBUG, 'all';
    }
}

package CPAN::Index;
use vars qw($last_time $date_of_03);
@CPAN::Index::ISA = qw(CPAN::Debug);
$last_time ||= 0;
$date_of_03 ||= 0;

#-> sub CPAN::Index::force_reload ;
sub force_reload {
    my($class) = @_;
    $CPAN::Index::last_time = 0;
    $class->reload(1);
}

#-> sub CPAN::Index::reload ;
sub reload {
    my($cl,$force) = @_;
    my $time = time;

    # XXX check if a newer one is available. (We currently read it from time to time)
    for ($CPAN::Config->{index_expire}) {
	$_ = 0.001 unless $_ > 0.001;
    }
    return if $last_time + $CPAN::Config->{index_expire}*86400 > $time;
    my($debug,$t2);
    $last_time = $time;

    $cl->read_authindex($cl->reload_x(
				      "authors/01mailrc.txt.gz",
				      "01mailrc.gz",
				      $force));
    $t2 = time;
    $debug = "timing reading 01[".($t2 - $time)."]";
    $time = $t2;
    return if $CPAN::Signal; # this is sometimes lengthy
    $cl->read_modpacks($cl->reload_x(
				     "modules/02packages.details.txt.gz",
				     "02packag.gz",
				     $force));
    $t2 = time;
    $debug .= "02[".($t2 - $time)."]";
    $time = $t2;
    return if $CPAN::Signal; # this is sometimes lengthy
    $cl->read_modlist($cl->reload_x(
				    "modules/03modlist.data.gz",
				    "03mlist.gz",
				    $force));
    $t2 = time;
    $debug .= "03[".($t2 - $time)."]";
    $time = $t2;
    CPAN->debug($debug) if $CPAN::DEBUG;
}

#-> sub CPAN::Index::reload_x ;
sub reload_x {
    my($cl,$wanted,$localname,$force) = @_;
    $force ||= 0;
    CPAN::Config->load; # we should guarantee loading wherever we rely on Config XXX
    my $abs_wanted = CPAN->catfile($CPAN::Config->{'keep_source_where'},$localname);
    if (
	-f $abs_wanted &&
	-M $abs_wanted < $CPAN::Config->{'index_expire'} &&
	!$force
       ) {
	my $s = $CPAN::Config->{'index_expire'} == 1 ? "" : "s";
	$cl->debug(qq{$abs_wanted younger than $CPAN::Config->{'index_expire'} }.
		   qq{day$s. I\'ll use that.});
	return $abs_wanted;
    } else {
	$force ||= 1;
    }
    return CPAN::FTP->localize($wanted,$abs_wanted,$force);
}

#-> sub CPAN::Index::read_authindex ;
sub read_authindex {
    my($cl,$index_target) = @_;
    my $pipe = "$CPAN::Config->{gzip} --decompress --stdout $index_target";
    print "Going to read $index_target\n";
    my $fh = FileHandle->new("$pipe|");
    while (<$fh>) {
	chomp;
	my($userid,$fullname,$email) = /alias\s+(\S+)\s+\"([^\"\<]+)\s+<([^\>]+)\>\"/;
	next unless $userid && $fullname && $email;

	# instantiate an author object
 	my $userobj = $CPAN::META->instance('CPAN::Author',$userid);
	$userobj->set('FULLNAME' => $fullname, 'EMAIL' => $email);
	return if $CPAN::Signal;
    }
    $fh->close;
    $? and Carp::croak "FAILED $pipe: exit status [$?]";
}

#-> sub CPAN::Index::read_modpacks ;
sub read_modpacks {
    my($cl,$index_target) = @_;
    my $pipe = "$CPAN::Config->{gzip} --decompress --stdout $index_target";
    print "Going to read $index_target\n";
    my $fh = FileHandle->new("$pipe|");
    while (<$fh>) {
	last if /^\s*$/;
    }
    while (<$fh>) {
	chomp;
	my($mod,$version,$dist) = split;
###	$version =~ s/^\+//;

	# if it as a bundle, instatiate a bundle object
	my($bundle,$id,$userid);
	
	if ($mod eq 'CPAN') {
	    local($^W)= 0;
	    if ($version > $CPAN::VERSION){
		print qq{
  There\'s a new CPAN.pm version (v$version) available!
  You might want to try
    install CPAN
    reload cpan
  without quitting the current session. It should be a seemless upgrade
  while we are running...
};
		sleep 2;
		print qq{\n};
	    }
	    last if $CPAN::Signal;
	} elsif ($mod =~ /^Bundle::(.*)/) {
	    $bundle = $1;
	}

	if ($bundle){
	    $id =  $CPAN::META->instance('CPAN::Bundle',$mod);
###	    $id->set('CPAN_VERSION' => $version, 'CPAN_FILE' => $dist);
# This "next" makes us faster but if the job is running long, we ignore
# rereads which is bad. So we have to be a bit slower again.
#	} elsif ($CPAN::META->exists('CPAN::Module',$mod)) {
#	    next;
	} else {
	    # instantiate a module object
	    $id = $CPAN::META->instance('CPAN::Module',$mod);
###	    $id->set('CPAN_VERSION' => $version, 'CPAN_FILE' => $dist)
###		if $id->cpan_version ne $version || $id->cpan_file ne $dist; # good speed in here
	}

	if ($id->cpan_file ne $dist){
	    # determine the author
	    ($userid) = $dist =~ /([^\/]+)/;
	    $id->set(
		     'CPAN_USERID' => $userid,
		     'CPAN_VERSION' => $version,
		     'CPAN_FILE' => $dist
		    );
	}

	# instantiate a distribution object
	unless ($CPAN::META->exists('CPAN::Distribution',$dist)) {
	    $CPAN::META->instance(
				  'CPAN::Distribution' => $dist
				 )->set(
					'CPAN_USERID' => $userid
				       );
	}

	return if $CPAN::Signal;
    }
    $fh->close;
    $? and Carp::croak "FAILED $pipe: exit status [$?]";
}

#-> sub CPAN::Index::read_modlist ;
sub read_modlist {
    my($cl,$index_target) = @_;
    my $pipe = "$CPAN::Config->{gzip} --decompress --stdout $index_target";
    print "Going to read $index_target\n";
    my $fh = FileHandle->new("$pipe|");
    my $eval;
    while (<$fh>) {
	if (/^Date:\s+(.*)/){
	    return if $date_of_03 eq $1;
	    ($date_of_03) = $1;
	}
	last if /^\s*$/;
    }
    local($/) = undef;
    $eval = <$fh>;
    $fh->close;
    $eval .= q{CPAN::Modulelist->data;};
    local($^W) = 0;
    my($comp) = Safe->new("CPAN::Safe1");
    my $ret = $comp->reval($eval);
    Carp::confess($@) if $@;
    return if $CPAN::Signal;
    for (keys %$ret) {
	my $obj = $CPAN::META->instance(CPAN::Module,$_);
	$obj->set(%{$ret->{$_}});
	return if $CPAN::Signal;
    }
}

package CPAN::InfoObj;
@CPAN::InfoObj::ISA = qw(CPAN::Debug);

#-> sub CPAN::InfoObj::new ;
sub new { my $this = bless {}, shift; %$this = @_; $this }

#-> sub CPAN::InfoObj::set ;
sub set {
    my($self,%att) = @_;
    my(%oldatt) = %$self;
    %$self = (%oldatt, %att);
}

#-> sub CPAN::InfoObj::id ;
sub id { shift->{'ID'} }

#-> sub CPAN::InfoObj::as_glimpse ;
sub as_glimpse {
    my($self) = @_;
    my(@m);
    my $class = ref($self);
    $class =~ s/^CPAN:://;
    push @m, sprintf "%-15s %s\n", $class, $self->{ID};
    join "", @m;
}

#-> sub CPAN::InfoObj::as_string ;
sub as_string {
    my($self) = @_;
    my(@m);
    my $class = ref($self);
    $class =~ s/^CPAN:://;
    push @m, $class, " id = $self->{ID}\n";
    for (sort keys %$self) {
	next if $_ eq 'ID';
	my $extra = "";
	$_ eq "CPAN_USERID" and $extra = " (".$self->author.")";
	if (ref($self->{$_}) eq "ARRAY") { # Should we setup a language interface? XXX
	    push @m, sprintf "    %-12s %s%s\n", $_, "@{$self->{$_}}", $extra;
	} else {
	    push @m, sprintf "    %-12s %s%s\n", $_, $self->{$_}, $extra;
	}
    }
    join "", @m, "\n";
}

#-> sub CPAN::InfoObj::author ;
sub author {
    my($self) = @_;
    $CPAN::META->instance(CPAN::Author,$self->{CPAN_USERID})->fullname;
}

package CPAN::Author;
@CPAN::Author::ISA = qw(CPAN::InfoObj);

#-> sub CPAN::Author::as_glimpse ;
sub as_glimpse {
    my($self) = @_;
    my(@m);
    my $class = ref($self);
    $class =~ s/^CPAN:://;
    push @m, sprintf "%-15s %s (%s)\n", $class, $self->{ID}, $self->fullname;
    join "", @m;
}

# Dead code, I would have liked to have,,, but it was never reached,,,
#sub make {
#    my($self) = @_;
#    return "Don't be silly, you can't make $self->{FULLNAME} ;-)\n";
#}

#-> sub CPAN::Author::fullname ;
sub fullname { shift->{'FULLNAME'} }
*name = \&fullname;
#-> sub CPAN::Author::email ;
sub email    { shift->{'EMAIL'} }

package CPAN::Distribution;
@CPAN::Distribution::ISA = qw(CPAN::InfoObj);

#-> sub CPAN::Distribution::called_for ;
sub called_for {
    my($self,$id) = @_;
    $self->{'CALLED_FOR'} = $id if defined $id;
    return $self->{'CALLED_FOR'};
}

#-> sub CPAN::Distribution::get ;
sub get {
    my($self) = @_;
  EXCUSE: {
	my @e;
	exists $self->{'build_dir'} and push @e,
	    "Unwrapped into directory $self->{'build_dir'}";
	print join "", map {"  $_\n"} @e and return if @e;
    }
    my($local_file);
    my($local_wanted) =
	 CPAN->catfile(
			$CPAN::Config->{keep_source_where},
			"authors",
			"id",
			split("/",$self->{ID})
		       );

    $self->debug("Doing localize") if $CPAN::DEBUG;
    $local_file = CPAN::FTP->localize("authors/id/$self->{ID}", $local_wanted);
    $self->{localfile} = $local_file;
    my $builddir = $CPAN::META->{cachemgr}->dir;
    $self->debug("doing chdir $builddir") if $CPAN::DEBUG;
    chdir $builddir or Carp::croak("Couldn't chdir $builddir: $!");
    my $packagedir;

    $self->debug("local_file[$local_file]") if $CPAN::DEBUG;
    if ($CPAN::META->hasMD5) {
	$self->verifyMD5;
    }
    if ($local_file =~ /(\.tar\.(gz|Z)|\.tgz|\.zip)$/i){
	$self->debug("Removing tmp") if $CPAN::DEBUG;
	File::Path::rmtree("tmp");
	mkdir "tmp", 0777 or Carp::croak "Couldn't mkdir tmp: $!";
	chdir "tmp";
	$self->debug("Changed directory to tmp") if $CPAN::DEBUG;
	if ($local_file =~ /z$/i){
	    $self->{archived} = "tar";
	    if (system("$CPAN::Config->{gzip} --decompress --stdout $local_file | $CPAN::Config->{tar} xvf -")== 0) {
		$self->{unwrapped} = "YES";
	    } else {
		$self->{unwrapped} = "NO";
	    }
	} elsif ($local_file =~ /zip$/i) {
	    $self->{archived} = "zip";
	    if (system("$CPAN::Config->{unzip} $local_file") == 0) {
		$self->{unwrapped} = "YES";
	    } else {
		$self->{unwrapped} = "NO";
	    }
	}
	# Let's check if the package has its own directory.
	opendir DIR, "." or Carp::croak("Weird: couldn't opendir .: $!");
	my @readdir = grep $_ !~ /^\.\.?$/, readdir DIR; ### MAC??
	closedir DIR;
	my ($distdir,$packagedir);
	if (@readdir == 1 && -d $readdir[0]) {
	    $distdir = $readdir[0];
	    $packagedir = $CPAN::META->catdir($builddir,$distdir);
	    -d $packagedir and print "Removing previously used $packagedir\n";
	    File::Path::rmtree($packagedir);
	    rename($distdir,$packagedir) or Carp::confess("Couldn't rename $distdir to $packagedir: $!");
	} else {
	    my $pragmatic_dir = $self->{'CPAN_USERID'} . '000';
	    $pragmatic_dir =~ s/\W_//g;
	    $pragmatic_dir++ while -d "../$pragmatic_dir";
	    $packagedir = $CPAN::META->catdir($builddir,$pragmatic_dir);
	    File::Path::mkpath($packagedir);
	    my($f);
	    for $f (@readdir) { # is already without "." and ".."
		my $to = $CPAN::META->catdir($packagedir,$f);
		rename($f,$to) or Carp::confess("Couldn't rename $f to $to: $!");
	    }
	}
	$self->{'build_dir'} = $packagedir;

	chdir "..";
	$self->debug("Changed directory to .. (self is $self [".$self->as_string."])")
	    if $CPAN::DEBUG;
	File::Path::rmtree("tmp");
	if ($CPAN::Config->{keep_source_where} =~ /^no/i ){
	    print "Going to unlink $local_file\n";
	    unlink $local_file or Carp::carp "Couldn't unlink $local_file";
	}
	my($makefilepl) = $CPAN::META->catfile($packagedir,"Makefile.PL");
	unless (-f $makefilepl) {
	    my($configure) = $CPAN::META->catfile($packagedir,"Configure");
	    if (-f $configure) {
		# do we have anything to do?
		$self->{'configure'} = $configure;
	    } else {
		my $fh = FileHandle->new(">$makefilepl")
		    or Carp::croak("Could not open >$makefilepl");
		my $cf = $self->called_for || "unknown";
		$fh->print(qq{
# This Makefile.PL has been autogenerated by the module CPAN.pm
# Autogenerated on: }.scalar localtime().qq{
		    use ExtUtils::MakeMaker;
		    WriteMakefile(NAME => q[$cf]);
});
		print qq{Package comes without Makefile.PL.\n}.
		    qq{  Writing one on our own (calling it $cf)\n};
	    }
	}
    } else {
	$self->{archived} = "NO";
    }
    return $self;
}

#-> sub CPAN::Distribution::new ;
sub new {
    my($class,%att) = @_;

    $CPAN::META->{cachemgr} ||= CPAN::CacheMgr->new();

    my $this = { %att };
    return bless $this, $class;
}

#-> sub CPAN::Distribution::look ;
sub look {
    my($self) = @_;
    if (  $CPAN::Config->{'shell'} ) {
	print qq{
Trying to open a subshell in the build directory...
};
    } else {
	print qq{
Your configuration does not define a value for subshells.
Please define it with "o conf shell <your shell>"
};
	return;
    }
    my $dist = $self->id;
    my $dir  = $self->dir or $self->get;
    $dir = $self->dir;
    my $getcwd;
    $getcwd = $CPAN::Config->{'getcwd'} || 'cwd';
    my $pwd  = Cwd->$getcwd();
    chdir($dir);
    print qq{Working directory is $dir.\n};
    system($CPAN::Config->{'shell'}) == 0 or die "Subprocess shell error";
    chdir($pwd);
}

#-> sub CPAN::Distribution::readme ;
sub readme {
    my($self) = @_;
    my($dist) = $self->id;
    my($sans,$suffix) = $dist =~ /(.+)\.(tgz|tar[\._-]gz|tar\.Z|zip)$/;
    $self->debug("sans[$sans] suffix[$suffix]\n") if $CPAN::DEBUG;
    my($local_file);
    my($local_wanted) =
	 CPAN->catfile(
			$CPAN::Config->{keep_source_where},
			"authors",
			"id",
			split("/","$sans.readme"),
		       );
    $self->debug("Doing localize") if $CPAN::DEBUG;
    $local_file = CPAN::FTP->localize("authors/id/$sans.readme", $local_wanted);
    my $fh_pager = FileHandle->new;
    $fh_pager->open("|$CPAN::Config->{'pager'}")
	or die "Could not open pager $CPAN::Config->{'pager'}: $!";
    my $fh_readme = FileHandle->new;
    $fh_readme->open($local_file) or die "Could not open $local_file: $!";
    $fh_pager->print(<$fh_readme>);
}

#-> sub CPAN::Distribution::verifyMD5 ;
sub verifyMD5 {
    my($self) = @_;
  EXCUSE: {
	my @e;
	$self->{MD5_STATUS} ||= "";
	$self->{MD5_STATUS} eq "OK" and push @e, "MD5 Checksum was ok";
	print join "", map {"  $_\n"} @e and return if @e;
    }
    my($local_file);
    my(@local) = split("/",$self->{ID});
    my($basename) = pop @local;
    push @local, "CHECKSUMS";
    my($local_wanted) =
	CPAN->catfile(
		      $CPAN::Config->{keep_source_where},
		      "authors",
		      "id",
		      @local
		     );
    local($") = "/";
    if (
	-f $local_wanted
	&&
	$self->MD5_check_file($local_wanted,$basename)
       ) {
	return $self->{MD5_STATUS} = "OK";
    }
    $local_file = CPAN::FTP->localize(
				      "authors/id/@local",
				      $local_wanted,
				      'force>:-{');
    my($checksum_pipe);
    if ($local_file) {
	# fine
    } else {
	$local[-1] .= ".gz";
	$local_file = CPAN::FTP->localize(
					  "authors/id/@local",
					  "$local_wanted.gz",
					  'force>:-{'
					 );
	my $system = "$CPAN::Config->{gzip} --decompress $local_file";
	system($system) == 0 or die "Could not uncompress $local_file";
	$local_file =~ s/\.gz$//;
    }
    $self->MD5_check_file($local_file,$basename);
}

#-> sub CPAN::Distribution::MD5_check_file ;
sub MD5_check_file {
    my($self,$lfile,$basename) = @_;
    my($cksum);
    my $fh = new FileHandle;
    local($/) = undef;
    if (open $fh, $lfile){
	my $eval = <$fh>;
	close $fh;
	my($comp) = Safe->new();
	$cksum = $comp->reval($eval);
	Carp::confess($@) if $@;
	if ($cksum->{$basename}->{md5}) {
	    $self->debug("Found checksum for $basename: $cksum->{$basename}->{md5}\n")
		if $CPAN::DEBUG;
	    my $file = $self->{localfile};
	    my $pipe = "$CPAN::Config->{gzip} --decompress --stdout $self->{localfile}|";
	    if (
		open($fh, $file) && $self->eq_MD5($fh,$cksum->{$basename}->{md5})
		or
		open($fh, $pipe) && $self->eq_MD5($fh,$cksum->{$basename}->{'md5-ungz'})
	       ){
		print "Checksum for $file ok\n";
		return $self->{MD5_STATUS} = "OK";
	    } else {
		print join(
			   "",
			   qq{Checksum mismatch for distribution file. },
			   qq{Please investigate.\n\n}
			  );
		print $self->as_string;
		print $CPAN::META->instance(
					    'CPAN::Author',
					    $self->{CPAN_USERID}
					   )->as_string;
		my $wrap = qq{I\'d recommend removing $self->{'localfile'}}.
		    qq{, put another URL at the top of the list of URLs to }.
		    qq{visit, and restart CPAN.pm. If all this doesn\'t help, }.
		    qq{please contact the author or your CPAN site admin};
		print Text::Wrap::wrap("","",$wrap);
		print "\n\n";
		sleep 3;
		return;
	    }
	    close $fh if fileno($fh);
	} else {
	    $self->{MD5_STATUS} ||= "";
	    if ($self->{MD5_STATUS} eq "NIL") {
		print "\nNo md5 checksum for $basename in local $lfile.";
		print "Removing $lfile\n";
		unlink $lfile or print "Could not unlink: $!";
		sleep 1;
	    }
	    $self->{MD5_STATUS} = "NIL";
	    return;
	}
    } else {
	Carp::carp "Could not open $lfile for reading";
    }
}

#-> sub CPAN::Distribution::eq_MD5 ;
sub eq_MD5 {
    my($self,$fh,$expectMD5) = @_;
    my $md5 = new MD5;
    $md5->addfile($fh);
    my $hexdigest = $md5->hexdigest;
    $hexdigest eq $expectMD5;
}

#-> sub CPAN::Distribution::force ;
sub force {
    my($self) = @_;
    $self->{'force_update'}++;
    delete $self->{'MD5_STATUS'};
    delete $self->{'archived'};
    delete $self->{'build_dir'};
    delete $self->{'localfile'};
    delete $self->{'make'};
    delete $self->{'install'};
    delete $self->{'unwrapped'};
    delete $self->{'writemakefile'};
}

#-> sub CPAN::Distribution::perl ;
sub perl {
    my($self) = @_;
    my($perl) = MM->file_name_is_absolute($^X) ? $^X : "";
    my $getcwd = $CPAN::Config->{'getcwd'} || 'cwd';
    my $pwd  = Cwd->$getcwd();
    my $candidate = $CPAN::META->catfile($pwd,$^X);
    $perl ||= $candidate if MM->maybe_command($candidate);
    unless ($perl) {
	my ($component,$perl_name);
      DIST_PERLNAME: foreach $perl_name ($^X, 'perl', 'perl5', "perl$]") {
	    PATH_COMPONENT: foreach $component (MM->path(), $Config::Config{'binexp'}) {
		  next unless defined($component) && $component;
		  my($abs) = MM->catfile($component,$perl_name);
		  if (MM->maybe_command($abs)) {
		      $perl = $abs;
		      last DIST_PERLNAME;
		  }
	      }
	  }
    }
    $perl;
}

#-> sub CPAN::Distribution::make ;
sub make {
    my($self) = @_;
    $self->debug($self->id) if $CPAN::DEBUG;
    print "Running make\n";
    $self->get;
  EXCUSE: {
	my @e;
	$self->{archived} eq "NO" and push @e,
	"Is neither a tar nor a zip archive.";

	$self->{unwrapped} eq "NO" and push @e,
	"had problems unarchiving. Please build manually";

	exists $self->{writemakefile} &&
	    $self->{writemakefile} eq "NO" and push @e,
	    "Had some problem writing Makefile";

	defined $self->{'make'} and push @e,
	"Has already been processed within this session";

	print join "", map {"  $_\n"} @e and return if @e;
    }
    print "\n  CPAN.pm: Going to build ".$self->id."\n\n";
    my $builddir = $self->dir;
    chdir $builddir or Carp::croak("Couldn't chdir $builddir: $!");
    $self->debug("Changed directory to $builddir") if $CPAN::DEBUG;

    my $system;
    if ($self->{'configure'}) {
	$system = $self->{'configure'};
    } else {
	my($perl) = $self->perl or die "Couldn\'t find executable perl\n";
	my $switch = "";
# This needs a handler that can be turned on or off:
#	$switch = "-MExtUtils::MakeMaker ".
#	    "-Mops=:default,:filesys_read,:filesys_open,require,chdir"
#	    if $] > 5.00310;
	$system = "$perl $switch Makefile.PL $CPAN::Config->{makepl_arg}";
    }
    {
	local($SIG{ALRM}) = sub { die "inactivity_timeout reached\n" };
	my($ret,$pid);
	$@ = "";
	if ($CPAN::Config->{inactivity_timeout}) {
	    eval {
		alarm $CPAN::Config->{inactivity_timeout};
		local $SIG{CHLD} = sub { wait };
		if (defined($pid = fork)) {
		    if ($pid) { #parent
			wait;
		    } else {    #child
			exec $system;
		    }
		} else {
		    print "Cannot fork: $!";
		    return;
		}
	    };
	    alarm 0;
	    if ($@){
		kill 9, $pid;
		waitpid $pid, 0;
		print $@;
		$self->{writemakefile} = "NO - $@";
		$@ = "";
		return;
	    }
	} else {
	    $ret = system($system);
	    if ($ret != 0) {
		$self->{writemakefile} = "NO";
		return;
	    }
	}
    }
    $self->{writemakefile} = "YES";
    return if $CPAN::Signal;
    $system = join " ", $CPAN::Config->{'make'}, $CPAN::Config->{make_arg};
    if (system($system) == 0) {
	 print "  $system -- OK\n";
	 $self->{'make'} = "YES";
    } else {
	 $self->{writemakefile} = "YES";
	 $self->{'make'} = "NO";
	 print "  $system -- NOT OK\n";
    }
}

#-> sub CPAN::Distribution::test ;
sub test {
    my($self) = @_;
    $self->make;
    return if $CPAN::Signal;
    print "Running make test\n";
  EXCUSE: {
	my @e;
	exists $self->{'make'} or push @e,
	"Make had some problems, maybe interrupted? Won't test";

	exists $self->{'make'} and
	    $self->{'make'} eq 'NO' and
		push @e, "Oops, make had returned bad status";

	exists $self->{'build_dir'} or push @e, "Has no own directory";
	print join "", map {"  $_\n"} @e and return if @e;
    }
    chdir $self->{'build_dir'} or Carp::croak("Couldn't chdir to $self->{'build_dir'}");
    $self->debug("Changed directory to $self->{'build_dir'}") if $CPAN::DEBUG;
    my $system = join " ", $CPAN::Config->{'make'}, "test";
    if (system($system) == 0) {
	 print "  $system -- OK\n";
	 $self->{'make_test'} = "YES";
    } else {
	 $self->{'make_test'} = "NO";
	 print "  $system -- NOT OK\n";
    }
}

#-> sub CPAN::Distribution::clean ;
sub clean {
    my($self) = @_;
    print "Running make clean\n";
  EXCUSE: {
	my @e;
	exists $self->{'build_dir'} or push @e, "Has no own directory";
	print join "", map {"  $_\n"} @e and return if @e;
    }
    chdir $self->{'build_dir'} or Carp::croak("Couldn't chdir to $self->{'build_dir'}");
    $self->debug("Changed directory to $self->{'build_dir'}") if $CPAN::DEBUG;
    my $system = join " ", $CPAN::Config->{'make'}, "clean";
    if (system($system) == 0) {
	print "  $system -- OK\n";
	$self->force;
    } else {
	# Hmmm, what to do if make clean failed?
    }
}

#-> sub CPAN::Distribution::install ;
sub install {
    my($self) = @_;
    $self->test;
    return if $CPAN::Signal;
    print "Running make install\n";
  EXCUSE: {
	my @e;
	exists $self->{'build_dir'} or push @e, "Has no own directory";

	exists $self->{'make'} or push @e,
	"Make had some problems, maybe interrupted? Won't install";

	exists $self->{'make'} and
	    $self->{'make'} eq 'NO' and
		push @e, "Oops, make had returned bad status";

	push @e, "make test had returned bad status, won't install without force"
	    if exists $self->{'make_test'} and
	    $self->{'make_test'} eq 'NO' and
	    ! $self->{'force_update'};

	exists $self->{'install'} and push @e,
	$self->{'install'} eq "YES" ?
	    "Already done" : "Already tried without success";

	print join "", map {"  $_\n"} @e and return if @e;
    }
    chdir $self->{'build_dir'} or Carp::croak("Couldn't chdir to $self->{'build_dir'}");
    $self->debug("Changed directory to $self->{'build_dir'}") if $CPAN::DEBUG;
    my $system = join " ", $CPAN::Config->{'make'}, "install", $CPAN::Config->{make_install_arg};
    my($pipe) = FileHandle->new("$system 2>&1 |");
    my($makeout) = "";
    while (<$pipe>){
	print;
	$makeout .= $_;
    }
    $pipe->close;
    if ($?==0) {
	 print "  $system -- OK\n";
	 $self->{'install'} = "YES";
    } else {
	 $self->{'install'} = "NO";
	 print "  $system -- NOT OK\n";
	 if ($makeout =~ /permission/s && $> > 0) {
	     print "    You may have to su to root to install the package\n";
	 }
    }
}

#-> sub CPAN::Distribution::dir ;
sub dir {
    shift->{'build_dir'};
}

package CPAN::Bundle;
@CPAN::Bundle::ISA = qw(CPAN::Module);

#-> sub CPAN::Bundle::as_string ;
sub as_string {
    my($self) = @_;
    $self->contains;
    $self->{INST_VERSION} = $self->inst_version;
    return $self->SUPER::as_string;
}

#-> sub CPAN::Bundle::contains ;
sub contains {
    my($self) = @_;
    my($parsefile) = $self->inst_file;
    unless ($parsefile) {
	# Try to get at it in the cpan directory
	$self->debug("no parsefile") if $CPAN::DEBUG;
	my $dist = $CPAN::META->instance('CPAN::Distribution',$self->{'CPAN_FILE'});
	$dist->get;
	$self->debug($dist->as_string) if $CPAN::DEBUG;
	my($todir) = $CPAN::META->catdir($CPAN::Config->{'cpan_home'},"Bundle");
	File::Path::mkpath($todir);
	my($me,$from,$to);
	($me = $self->id) =~ s/.*://;
	$from = $self->find_bundle_file($dist->{'build_dir'},"$me.pm");
	$to = $CPAN::META->catfile($todir,"$me.pm");
	File::Copy::copy($from, $to) or Carp::confess("Couldn't copy $from to $to: $!");
	$parsefile = $to;
    }
    my @result;
    my $fh = new FileHandle;
    local $/ = "\n";
    open($fh,$parsefile) or die "Could not open '$parsefile': $!";
    my $inpod = 0;
    $self->debug("parsefile[$parsefile]") if $CPAN::DEBUG;
    while (<$fh>) {
	$inpod = /^=(?!head1\s+CONTENTS)/ ? 0 : /^=head1\s+CONTENTS/ ? 1 : $inpod;
	next unless $inpod;
	next if /^=/;
	next if /^\s+$/;
	chomp;
	push @result, (split " ", $_, 2)[0];
    }
    close $fh;
    delete $self->{STATUS};
    $self->{CONTAINS} = join ", ", @result;
    $self->debug("CONTAINS[@result]") if $CPAN::DEBUG;
    @result;
}

#-> sub CPAN::Bundle::find_bundle_file
sub find_bundle_file {
    my($self,$where,$what) = @_;
    my $bu = $CPAN::META->catfile($where,$what);
    return $bu if -f $bu;
    my $manifest = $CPAN::META->catfile($where,"MANIFEST");
    unless (-f $manifest) {
	require ExtUtils::Manifest;
	my $getcwd = $CPAN::Config->{'getcwd'} || 'cwd';
	my $cwd = Cwd->$getcwd();
	chdir $where;
	ExtUtils::Manifest::mkmanifest();
	chdir $cwd;
    }
    my $fh = FileHandle->new($manifest) or Carp::croak("Couldn't open $manifest: $!");
    local($/) = "\n";
    while (<$fh>) {
	next if /^\s*\#/;
	my($file) = /(\S+)/;
	if ($file =~ m|Bundle/$what$|) {
	    $bu = $file;
	    return $CPAN::META->catfile($where,$bu);
	}
    }
    Carp::croak("Could't find a Bundle file in $where");
}

#-> sub CPAN::Bundle::inst_file ;
sub inst_file {
    my($self) = @_;
    my($me,$inst_file);
    ($me = $self->id) =~ s/.*://;
    $inst_file = $CPAN::META->catfile($CPAN::Config->{'cpan_home'},"Bundle", "$me.pm");
    return $self->{'INST_FILE'} = $inst_file if -f $inst_file;
#    $inst_file = 
    $self->SUPER::inst_file;
#    return $self->{'INST_FILE'} = $inst_file if -f $inst_file;
#    return $self->{'INST_FILE'}; # even if undefined?
}

#-> sub CPAN::Bundle::rematein ;
sub rematein {
    my($self,$meth) = @_;
    $self->debug("self[$self] meth[$meth]") if $CPAN::DEBUG;
    my($s);
    for $s ($self->contains) {
	my($type) = $s =~ m|/| ? 'CPAN::Distribution' :
	    $s =~ m|^Bundle::| ? 'CPAN::Bundle' : 'CPAN::Module';
	if ($type eq 'CPAN::Distribution') {
	    warn qq{
The Bundle }.$self->id.qq{ contains
explicitly a file $s.
};
	    sleep 3;
	}
	$CPAN::META->instance($type,$s)->$meth();
    }
}

#sub CPAN::Bundle::xs_file
sub xs_file {
    # If a bundle contains another that contains an xs_file we have
    # here, we just don't bother I suppose
    return 0;
}

#-> sub CPAN::Bundle::force ;
sub force   { shift->rematein('force',@_); }
#-> sub CPAN::Bundle::get ;
sub get     { shift->rematein('get',@_); }
#-> sub CPAN::Bundle::make ;
sub make    { shift->rematein('make',@_); }
#-> sub CPAN::Bundle::test ;
sub test    { shift->rematein('test',@_); }
#-> sub CPAN::Bundle::install ;
sub install { shift->rematein('install',@_); }
#-> sub CPAN::Bundle::clean ;
sub clean   { shift->rematein('clean',@_); }

#-> sub CPAN::Bundle::readme ;
sub readme  {
    my($self) = @_;
    my($file) = $self->cpan_file or print("No File found for bundle ", $self->id, "\n"), return;
    $self->debug("self[$self] file[$file]") if $CPAN::DEBUG;
    $CPAN::META->instance('CPAN::Distribution',$file)->readme;
}

package CPAN::Module;
@CPAN::Module::ISA = qw(CPAN::InfoObj);

#-> sub CPAN::Module::as_glimpse ;
sub as_glimpse {
    my($self) = @_;
    my(@m);
    my $class = ref($self);
    $class =~ s/^CPAN:://;
    push @m, sprintf "%-15s %-15s (%s)\n", $class, $self->{ID}, $self->cpan_file;
    join "", @m;
}

#-> sub CPAN::Module::as_string ;
sub as_string {
    my($self) = @_;
    my(@m);
    CPAN->debug($self) if $CPAN::DEBUG;
    my $class = ref($self);
    $class =~ s/^CPAN:://;
    local($^W) = 0;
    push @m, $class, " id = $self->{ID}\n";
    my $sprintf = "    %-12s %s\n";
    push @m, sprintf $sprintf, 'DESCRIPTION', $self->{description} if $self->{description};
    my $sprintf2 = "    %-12s %s (%s)\n";
    my($userid);
    if ($userid = $self->{'CPAN_USERID'} || $self->{'userid'}){
	push @m, sprintf(
			 $sprintf2,
			 'CPAN_USERID',
			 $userid,
			 CPAN::Shell->expand('Author',$userid)->fullname
			)
    }
    push @m, sprintf $sprintf, 'CPAN_VERSION', $self->{CPAN_VERSION} if $self->{CPAN_VERSION};
    push @m, sprintf $sprintf, 'CPAN_FILE', $self->{CPAN_FILE} if $self->{CPAN_FILE};
    my $sprintf3 = "    %-12s %1s%1s%1s%1s (%s,%s,%s,%s)\n";
    my(%statd,%stats,%statl,%stati);
    @statd{qw,? i c a b R M S,} = qw,unknown idea pre-alpha alpha beta released mature standard,;
    @stats{qw,? m d u n,}       = qw,unknown mailing-list developer comp.lang.perl.* none,;
    @statl{qw,? p c + o,}       = qw,unknown perl C C++ other,;
    @stati{qw,? f r O,}         = qw,unknown functions references+ties object-oriented,;
    $statd{' '} = 'unknown';
    $stats{' '} = 'unknown';
    $statl{' '} = 'unknown';
    $stati{' '} = 'unknown';
    push @m, sprintf(
		     $sprintf3,
		     'DSLI_STATUS',
		     $self->{statd},
		     $self->{stats},
		     $self->{statl},
		     $self->{stati},
		     $statd{$self->{statd}},
		     $stats{$self->{stats}},
		     $statl{$self->{statl}},
		     $stati{$self->{stati}}
		    ) if $self->{statd};
    my $local_file = $self->inst_file;
    if ($local_file && ! exists $self->{MANPAGE}) {
	my $fh = FileHandle->new($local_file) or Carp::croak("Couldn't open $local_file: $!");
	my $inpod = 0;
	my(@result);
	local $/ = "\n";
	while (<$fh>) {
	    $inpod = /^=(?!head1\s+NAME)/ ? 0 : /^=head1\s+NAME/ ? 1 : $inpod;
	    next unless $inpod;
	    next if /^=/;
	    next if /^\s+$/;
	    chomp;
	    push @result, $_;
	}
	close $fh;
	$self->{MANPAGE} = join " ", @result;
    }
    my($item);
    for $item (qw/MANPAGE CONTAINS/) {
	push @m, sprintf $sprintf, $item, $self->{$item} if exists $self->{$item};
    }
    push @m, sprintf $sprintf, 'INST_FILE', $local_file || "(not installed)";
    push @m, sprintf $sprintf, 'INST_VERSION', $self->inst_version if $local_file;
    join "", @m, "\n";
}

#-> sub CPAN::Module::cpan_file ;
sub cpan_file    {
    my $self = shift;
    CPAN->debug($self->id) if $CPAN::DEBUG;
    unless (defined $self->{'CPAN_FILE'}) {
	CPAN::Index->reload;
    }
    if (defined $self->{'CPAN_FILE'}){
	return $self->{'CPAN_FILE'};
    } elsif (defined $self->{'userid'}) {
	return "Contact Author ".$self->{'userid'}."=".$CPAN::META->instance(CPAN::Author,$self->{'userid'})->fullname
    } else {
	return "N/A";
    }
}

*name = \&cpan_file;

#-> sub CPAN::Module::cpan_version ;
sub cpan_version { shift->{'CPAN_VERSION'} }

#-> sub CPAN::Module::force ;
sub force {
    my($self) = @_;
    $self->{'force_update'}++;
}

#-> sub CPAN::Module::rematein ;
sub rematein {
    my($self,$meth) = @_;
    $self->debug($self->id) if $CPAN::DEBUG;
    my $cpan_file = $self->cpan_file;
    return if $cpan_file eq "N/A";
    return if $cpan_file =~ /^Contact Author/;
    my $pack = $CPAN::META->instance('CPAN::Distribution',$cpan_file);
    $pack->called_for($self->id);
    $pack->force if exists $self->{'force_update'};
    $pack->$meth();
    delete $self->{'force_update'};
}

#-> sub CPAN::Module::readme ;
sub readme { shift->rematein('readme') }
#-> sub CPAN::Module::look ;
sub look { shift->rematein('look') }
#-> sub CPAN::Module::get ;
sub get    { shift->rematein('get',@_); }
#-> sub CPAN::Module::make ;
sub make   { shift->rematein('make') }
#-> sub CPAN::Module::test ;
sub test   { shift->rematein('test') }
#-> sub CPAN::Module::install ;
sub install {
    my($self) = @_;
    my($doit) = 0;
    my($latest) = $self->cpan_version;
    $latest ||= 0;
    my($inst_file) = $self->inst_file;
    my($have) = 0;
    if (defined $inst_file) {
	$have = $self->inst_version;
    }
    if (1){ # A block for scoping $^W, the if is just for the visual
            # appeal
	local($^W)=0;
	if ($inst_file && $have >= $latest && not exists $self->{'force_update'}) {
	    print $self->id, " is up to date.\n";
	} else {
	    $doit = 1;
	}
    }
    $self->rematein('install') if $doit;
}
#-> sub CPAN::Module::clean ;
sub clean  { shift->rematein('clean') }

#-> sub CPAN::Module::inst_file ;
sub inst_file {
    my($self) = @_;
    my($dir,@packpath);
    @packpath = split /::/, $self->{ID};
    $packpath[-1] .= ".pm";
    foreach $dir (@INC) {
	my $pmfile = CPAN->catfile($dir,@packpath);
	if (-f $pmfile){
	    return $pmfile;
	}
    }
    return;
}

#-> sub CPAN::Module::xs_file ;
sub xs_file {
    my($self) = @_;
    my($dir,@packpath);
    @packpath = split /::/, $self->{ID};
    push @packpath, $packpath[-1];
    $packpath[-1] .= "." . $Config::Config{'dlext'};
    foreach $dir (@INC) {
	my $xsfile = CPAN->catfile($dir,'auto',@packpath);
	if (-f $xsfile){
	    return $xsfile;
	}
    }
    return;
}

#-> sub CPAN::Module::inst_version ;
sub inst_version {
    my($self) = @_;
    my $parsefile = $self->inst_file or return 0;
    local($^W) = 0 if $] < 5.00303 && $ExtUtils::MakeMaker::VERSION < 5.38;
    my $have = MM->parse_version($parsefile);
    $have ||= 0;
    $have =~ s/\s+//g;
    $have ||= 0;
    $have;
}

# Do this after you have set up the whole inheritance
CPAN::Config->load unless defined $CPAN::No_Config_is_ok;

1;
__END__

=head1 NAME

CPAN - query, download and build perl modules from CPAN sites

=head1 SYNOPSIS

Interactive mode:

  perl -MCPAN -e shell;

Batch mode:

  use CPAN;

  autobundle, clean, install, make, recompile, test

=head1 DESCRIPTION

The CPAN module is designed to automate the make and install of perl
modules and extensions. It includes some searching capabilities and
knows how to use Net::FTP or LWP (or lynx or an external ftp client)
to fetch the raw data from the net.

Modules are fetched from one or more of the mirrored CPAN
(Comprehensive Perl Archive Network) sites and unpacked in a dedicated
directory.

The CPAN module also supports the concept of named and versioned
'bundles' of modules. Bundles simplify the handling of sets of
related modules. See BUNDLES below.

The package contains a session manager and a cache manager. There is
no status retained between sessions. The session manager keeps track
of what has been fetched, built and installed in the current
session. The cache manager keeps track of the disk space occupied by
the make processes and deletes excess space according to a simple FIFO
mechanism.

All methods provided are accessible in a programmer style and in an
interactive shell style.

=head2 Interactive Mode

The interactive mode is entered by running

    perl -MCPAN -e shell

which puts you into a readline interface. You will have most fun if
you install Term::ReadKey and Term::ReadLine to enjoy both history and
completion.

Once you are on the command line, type 'h' and the rest should be
self-explanatory.

The most common uses of the interactive modes are

=over 2

=item Searching for authors, bundles, distribution files and modules

There are corresponding one-letter commands C<a>, C<b>, C<d>, and C<m>
for each of the four categories and another, C<i> for any of the
mentioned four. Each of the four entities is implemented as a class
with slightly differing methods for displaying an object.

Arguments you pass to these commands are either strings matching exact
the identification string of an object or regular expressions that are
then matched case-insensitively against various attributes of the
objects. The parser recognizes a regualar expression only if you
enclose it between two slashes.

The principle is that the number of found objects influences how an
item is displayed. If the search finds one item, we display the result
of object-E<gt>as_string, but if we find more than one, we display
each as object-E<gt>as_glimpse. E.g.

    cpan> a ANDK     
    Author id = ANDK
	EMAIL        a.koenig@franz.ww.TU-Berlin.DE
	FULLNAME     Andreas K�nig


    cpan> a /andk/   
    Author id = ANDK
	EMAIL        a.koenig@franz.ww.TU-Berlin.DE
	FULLNAME     Andreas K�nig


    cpan> a /and.*rt/
    Author          ANDYD (Andy Dougherty)
    Author          MERLYN (Randal L. Schwartz)

=item make, test, install, clean  modules or distributions

These commands do indeed exist just as written above. Each of them
takes any number of arguments and investigates for each what it might
be. Is it a distribution file (recognized by embedded slashes), this
file is being processed. Is it a module, CPAN determines the
distribution file where this module is included and processes that.

Any C<make>, C<test>, and C<readme> are run unconditionally. A 

  install <distribution_file>

also is run unconditionally.  But for 

  install <module>

CPAN checks if an install is actually needed for it and prints
I<Foo up to date> in case the module doesnE<39>t need to be updated.

CPAN also keeps track of what it has done within the current session
and doesnE<39>t try to build a package a second time regardless if it
succeeded or not. The C<force > command takes as first argument the
method to invoke (currently: make, test, or install) and executes the
command from scratch.

Example:

    cpan> install OpenGL
    OpenGL is up to date.
    cpan> force install OpenGL
    Running make
    OpenGL-0.4/
    OpenGL-0.4/COPYRIGHT
    [...]

=item readme, look module or distribution

These two commands take only one argument, be it a module or a
distribution file. C<readme> displays the README of the associated
distribution file. C<Look> gets and untars (if not yet done) the
distribution file, changes to the appropriate directory and opens a
subshell process in that directory.

=back

=head2 CPAN::Shell

The commands that are available in the shell interface are methods in
the package CPAN::Shell. If you enter the shell command, all your
input is split by the Text::ParseWords::shellwords() routine which
acts like most shells do. The first word is being interpreted as the
method to be called and the rest of the words are treated as arguments
to this method.

=head2 autobundle

C<autobundle> writes a bundle file into the
C<$CPAN::Config-E<gt>{cpan_home}/Bundle> directory. The file contains
a list of all modules that are both available from CPAN and currently
installed within @INC. The name of the bundle file is based on the
current date and a counter.

=head2 recompile

recompile() is a very special command in that it takes no argument and
runs the make/test/install cycle with brute force over all installed
dynamically loadable extensions (aka XS modules) with 'force' in
effect. Primary purpose of this command is to finish a network
installation. Imagine, you have a common source tree for two different
architectures. You decide to do a completely independent fresh
installation. You start on one architecture with the help of a Bundle
file produced earlier. CPAN installs the whole Bundle for you, but
when you try to repeat the job on the second architecture, CPAN
responds with a C<"Foo up to date"> message for all modules. So you
will be glad to run recompile in the second architecture and
youE<39>re done.

Another popular use for C<recompile> is to act as a rescue in case your
perl breaks binary compatibility. If one of the modules that CPAN uses
is in turn depending on binary compatibility (so you cannot run CPAN
commands), then you should try the CPAN::Nox module for recovery.

=head2 The 4 Classes: Authors, Bundles, Modules, Distributions

Although it may be considered internal, the class hierarchie does
matter for both users and programmer. CPAN.pm deals with above
mentioned four classes, and all those classes share a set of
methods. It is a classical single polymorphism that is in effect.  A
metaclass object registers all objects of all kinds and indexes them
with a string. The strings referencing objects have a separated
namespace (well, not completely separated):

         Namespace                         Class

   words containing a "/" (slash)      Distribution
    words starting with Bundle::          Bundle
          everything else            Module or Author

Modules know their associated Distribution objects. They always refer
to the most recent official release. Developers may mark their
releases as unstable development versions (by inserting an underbar
into the visible version number), so not always is the default
distribution for a given module the really hottest and newest. If a
module Foo circulates on CPAN in both version 1.23 and 1.23_90,
CPAN.pm offers a convenient way to install version 1.23 by saying

    install Foo

This would install the complete distribution file (say
BAR/Foo-1.23.tar.gz) with all accompanying material in there. But if
you would like to install version 1.23_90, you need to know where the
distribution file resides on CPAN relative to the authors/id/
directory. If the author is BAR, this might be BAR/Foo-1.23_90.tar.gz,
so he would have say

    install BAR/Foo-1.23_90.tar.gz

The first example will be driven by an object of the class
CPAN::Module, the second by an object of class Distribution.

=head2 ProgrammerE<39>s interface

If you do not enter the shell, the available shell commands are both
available as methods (C<CPAN::Shell-E<gt>install(...)>) and as
functions in the calling package (C<install(...)>).

There's currently only one class that has a stable interface,
CPAN::Shell. All commands that are available in the CPAN shell are
methods of the class CPAN::Shell. The commands that produce listings
of modules (C<r>, C<autobundle>, C<u>) return a list of the IDs of all
modules within the list.

=over 2

=item expand($type,@things)

The IDs of all objects available within a program are strings that can
be expanded to the corresponding real objects with the
C<CPAN::Shell-E<gt>expand()> method. Expand returns a list of
CPAN::Module objects according to the C<@things> arguments given. In
scalar context it only returns the first element of the list.

=item Programming Examples

This enables the programmer to do operations like these:

    # install everything that is outdated on my disk:
    perl -MCPAN -e 'CPAN::Shell->install(CPAN::Shell->r)'

    # install my favorite programs if necessary:
    for $mod (qw(Net::FTP MD5 Data::Dumper)){
        my $obj = CPAN::Shell->expand('Module',$mod);
        $obj->install;
    }

=back

=head2 Cache Manager

Currently the cache manager only keeps track of the build directory
($CPAN::Config->{build_dir}). It is a simple FIFO mechanism that
deletes complete directories below C<build_dir> as soon as the size of
all directories there gets bigger than $CPAN::Config->{build_cache}
(in MB). The contents of this cache may be used for later
re-installations that you intend to do manually, but will never be
trusted by CPAN itself. This is due to the fact that the user might
use these directories for building modules on different architectures.

There is another directory ($CPAN::Config->{keep_source_where}) where
the original distribution files are kept. This directory is not
covered by the cache manager and must be controlled by the user. If
you choose to have the same directory as build_dir and as
keep_source_where directory, then your sources will be deleted with
the same fifo mechanism.

=head2 Bundles

A bundle is just a perl module in the namespace Bundle:: that does not
define any functions or methods. It usually only contains documentation.

It starts like a perl module with a package declaration and a $VERSION
variable. After that the pod section looks like any other pod with the
only difference, that I<one special pod section> exists starting with
(verbatim):

	=head1 CONTENTS

In this pod section each line obeys the format

        Module_Name [Version_String] [- optional text]

The only required part is the first field, the name of a module
(eg. Foo::Bar, ie. I<not> the name of the distribution file). The rest
of the line is optional. The comment part is delimited by a dash just
as in the man page header.

The distribution of a bundle should follow the same convention as
other distributions.

Bundles are treated specially in the CPAN package. If you say 'install
Bundle::Tkkit' (assuming such a bundle exists), CPAN will install all
the modules in the CONTENTS section of the pod.  You can install your
own Bundles locally by placing a conformant Bundle file somewhere into
your @INC path. The autobundle() command which is available in the
shell interface does that for you by including all currently installed
modules in a snapshot bundle file.

There is a meaningless Bundle::Demo available on CPAN. Try to install
it, it usually does no harm, just demonstrates what the Bundle
interface looks like.

=head2 Prerequisites

If you have a local mirror of CPAN and can access all files with
"file:" URLs, then you only need a perl better than perl5.003 to run
this module. Otherwise Net::FTP is strongly recommended. LWP may be
required for non-UNIX systems or if your nearest CPAN site is
associated with an URL that is not C<ftp:>.

If you have neither Net::FTP nor LWP, there is a fallback mechanism
implemented for an external ftp command or for an external lynx
command.

This module presumes that all packages on CPAN

=over 2

=item *

declare their $VERSION variable in an easy to parse manner. This
prerequisite can hardly be relaxed because it consumes by far too much
memory to load all packages into the running program just to determine
the $VERSION variable . Currently all programs that are dealing with
version use something like this

    perl -MExtUtils::MakeMaker -le \
        'print MM->parse_version($ARGV[0])' filename

If you are author of a package and wonder if your $VERSION can be
parsed, please try the above method.

=item *

come as compressed or gzipped tarfiles or as zip files and contain a
Makefile.PL (well we try to handle a bit more, but without much
enthusiasm).

=back

=head2 Debugging

The debugging of this module is pretty difficult, because we have
interferences of the software producing the indices on CPAN, of the
mirroring process on CPAN, of packaging, of configuration, of
synchronicity, and of bugs within CPAN.pm.

In interactive mode you can try "o debug" which will list options for
debugging the various parts of the package. The output may not be very
useful for you as it's just a byproduct of my own testing, but if you
have an idea which part of the package may have a bug, it's sometimes
worth to give it a try and send me more specific output. You should
know that "o debug" has built-in completion support.

=head2 Floppy, Zip, and all that Jazz

CPAN.pm works nicely without network too. If you maintain machines
that are not networked at all, you should consider working with file:
URLs. Of course, you have to collect your modules somewhere first. So
you might use CPAN.pm to put together all you need on a networked
machine. Then copy the $CPAN::Config->{keep_source_where} (but not
$CPAN::Config->{build_dir}) directory on a floppy. This floppy is kind
of a personal CPAN. CPAN.pm on the non-networked machines works nicely
with this floppy.

=head1 CONFIGURATION

When the CPAN module is installed a site wide configuration file is
created as CPAN/Config.pm. The default values defined there can be
overridden in another configuration file: CPAN/MyConfig.pm. You can
store this file in $HOME/.cpan/CPAN/MyConfig.pm if you want, because
$HOME/.cpan is added to the search path of the CPAN module before the
use() or require() statements.

Currently the following keys in the hash reference $CPAN::Config are
defined:

  build_cache        size of cache for directories to build modules
  build_dir          locally accessible directory to build modules
  index_expire       after how many days refetch index files
  cpan_home          local directory reserved for this package
  gzip		     location of external program gzip
  inactivity_timeout breaks interactive Makefile.PLs after that
                     many seconds inactivity. Set to 0 to never break.
  inhibit_startup_message
                     if true, does not print the startup message
  keep_source        keep the source in a local directory?
  keep_source_where  where keep the source (if we do)
  make               location of external program make
  make_arg	     arguments that should always be passed to 'make'
  make_install_arg   same as make_arg for 'make install'
  makepl_arg	     arguments passed to 'perl Makefile.PL'
  pager              location of external program more (or any pager)
  tar                location of external program tar
  unzip              location of external program unzip
  urllist	     arrayref to nearby CPAN sites (or equivalent locations)

You can set and query each of these options interactively in the cpan
shell with the command set defined within the C<o conf> command:

=over 2

=item o conf E<lt>scalar optionE<gt>

prints the current value of the I<scalar option>

=item o conf E<lt>scalar optionE<gt> E<lt>valueE<gt>

Sets the value of the I<scalar option> to I<value>

=item o conf E<lt>list optionE<gt>

prints the current value of the I<list option> in MakeMaker's
neatvalue format.

=item o conf E<lt>list optionE<gt> [shift|pop]

shifts or pops the array in the I<list option> variable

=item o conf E<lt>list optionE<gt> [unshift|push|splice] E<lt>listE<gt>

works like the corresponding perl commands.

=back

=head1 SECURITY

There's no strong security layer in CPAN.pm. CPAN.pm helps you to
install foreign, unmasked, unsigned code on your machine. We compare
to a checksum that comes from the net just as the distribution file
itself. If somebody has managed to tamper with the distribution file,
they may have as well tampered with the CHECKSUMS file. Future
development will go towards strong authentification.

=head1 EXPORT

Most functions in package CPAN are exported per default. The reason
for this is that the primary use is intended for the cpan shell or for
oneliners.

=head1 BUGS

we should give coverage for _all_ of the CPAN and not just the
__PAUSE__ part, right? In this discussion CPAN and PAUSE have become
equal -- but they are not. PAUSE is authors/ and modules/. CPAN is
PAUSE plus the clpa/, doc/, misc/, ports/, src/, scripts/.

Future development should be directed towards a better intergration of
the other parts.

=head1 AUTHOR

Andreas K�nig E<lt>a.koenig@mind.deE<gt>

=head1 SEE ALSO

perl(1), CPAN::Nox(3)

=cut

