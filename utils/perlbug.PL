#!/usr/local/bin/perl

use Config;
use File::Basename qw(&basename &dirname);

# List explicitly here the variables you want Configure to
# generate.  Metaconfig only looks for shell variables, so you
# have to mention them as if they were shell variables, not
# %Config entries.  Thus you write
#  $startperl
# to ensure Configure will look for $Config{startperl}.

# This forces PL files to create target in same directory as PL file.
# This is so that make depend always knows where to find PL derivatives.
chdir dirname($0);
$file = basename($0, '.PL');
$file .= '.com' if $^O eq 'VMS';

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

# In this section, perl variables will be expanded during extraction.
# You can use $Config{...} to use Configure variables.

print OUT <<"!GROK!THIS!";
$Config{startperl}
    eval 'exec $Config{perlpath} -S \$0 \${1+"\$@"}'
	if \$running_under_some_shell;
!GROK!THIS!

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';

use Config;
use Getopt::Std;

BEGIN {
	eval "use Mail::Send;";
	$::HaveSend = ($@ eq "");
	eval "use Mail::Util;";
	$::HaveUtil = ($@ eq "");
};


use strict;

sub paraprint;


my($Version) = "1.17";

# Changed in 1.06 to skip Mail::Send and Mail::Util if not available.
# Changed in 1.07 to see more sendmail execs, and added pipe output.
# Changed in 1.08 to use correct address for sendmail.
# Changed in 1.09 to close the REP file before calling it up in the editor.
#                 Also removed some old comments duplicated elsewhere.
# Changed in 1.10 to run under VMS without Mail::Send; also fixed
#                 temp filename generation.
# Changed in 1.11 to clean up some text and removed Mail::Send deactivator.
# Changed in 1.12 to check for editor errors, make save/send distinction
#                 clearer and add $ENV{REPLYTO}.
# Changed in 1.13 to hopefully make it more difficult to accidentally
#                 send mail
# Changed in 1.14 to make the prompts a little more clear on providing
#                 helpful information. Also let file read fail gracefully.
# Changed in 1.15 to add warnings to stop people using perlbug for non-bugs.
#                 Also report selected environment variables.
# Changed in 1.16 to include @INC, and allow user to re-edit if no changes.
# Changed in 1.17 Win32 support added.  GSAR 97-04-12

# TODO: Allow the user to re-name the file on mail failure, and
#       make sure failure (transmission-wise) of Mail::Send is 
#       accounted for.

my( $file, $usefile, $cc, $address, $perlbug, $testaddress, $filename,
    $subject, $from, $verbose, $ed, 
    $fh, $me, $Is_MSWin32, $Is_VMS, $msg, $body, $andcc, %REP);

Init();

if($::opt_h) { Help(); exit; }

if(!-t STDIN) {
	paraprint <<EOF;
Please use perlbug interactively. If you want to 
include a file, you can use the -f switch.
EOF
	die "\n";
}

if($::opt_d or !-t STDOUT) { Dump(*STDOUT); exit; }

Query();
Edit() unless $usefile;
NowWhat();
Send();

exit;

sub Init {
 
	# -------- Setup --------

	$Is_MSWin32 = $^O eq 'MSWin32';
	$Is_VMS = $^O eq 'VMS';

	getopts("dhva:s:b:f:r:e:SCc:t");
	

	# This comment is needed to notify metaconfig that we are
	# using the $perladmin, $cf_by, and $cf_time definitions.


	# -------- Configuration ---------
	
	# perlbug address
	$perlbug = 'perlbug@perl.com';
	
	# Test address
	$testaddress = 'perlbug-test@perl.com';
	
	# Target address
	$address = $::opt_a || ($::opt_t ? $testaddress : $perlbug);

	# Possible administrator addresses, in order of confidence
	# (Note that cf_email is not mentioned to metaconfig, since
	# we don't really want it. We'll just take it if we have to.)
	$cc = ($::opt_C ? "" : (
		$::opt_c || $::Config{perladmin} || $::Config{cf_email} || $::Config{cf_by}
		));
	
	# Users address, used in message and in Reply-To header
	$from = $::opt_r || "";

	# Include verbose configuration information
	$verbose = $::opt_v || 0;

	# Subject of bug-report message
	$subject = $::opt_s || "";

	# Send a file
	$usefile = ($::opt_f || 0);
	
	# File to send as report
	$file = $::opt_f || "";

	# Body of report
	$body = $::opt_b || "";

	# Editor
	$ed = (	$::opt_e || $ENV{VISUAL} || $ENV{EDITOR} || $ENV{EDIT} || 
		      ($Is_VMS ? "edit/tpu" : $Is_MSWin32 ? "notepad" : "vi")
	      );
	      
      
	# My username
	$me = ($Is_MSWin32 ? $ENV{'USERNAME'} : getpwuid($<));

}


sub Query {

	# Explain what perlbug is
	
	paraprint <<EOF;
This program provides an easy way to create a message reporting a bug
in perl, and e-mail it to $address.  It is *NOT* intended for
sending test messages or simply verifying that perl works, *NOR* is it
intended for reporting bugs in third-party perl modules.  It is *ONLY*
a means of reporting verifiable problems with the core perl distribution,
and any solutions to such problems, to the people who maintain perl.

If you're just looking for help with perl, try posting to the Usenet
newsgroup comp.lang.perl.misc.  If you're looking for help with using
perl with CGI, try posting to comp.infosystems.www.programming.cgi.

EOF


	# Prompt for subject of message, if needed
	if(! $subject) {
		paraprint <<EOF;
First of all, please provide a subject for the 
message. It should be a concise description of 
the bug or problem. "perl bug" or "perl problem"
is not a concise description.

EOF
		print "Subject: ";
	
		$subject = <>;
		chop $subject;
	
		my($err)=0;
		while( $subject =~ /^\s*$/ ) {
			print "\nPlease enter a subject: ";
			$subject = <>;
			chop $subject;
			if($err++>5) {
				die "Aborting.\n";
			}
		}
	}
	

	# Prompt for return address, if needed
	if( !$from) {

		# Try and guess return address
		my($domain);
		
		if($::HaveUtil) {
			$domain = Mail::Util::maildomain();
		} elsif ($Is_MSWin32) {
			$domain = $ENV{'USERDOMAIN'};
		} elsif ($Is_VMS) {
			require Sys::Hostname;
			$domain = Sys::Hostname::hostname();
		} else {
			$domain = `hostname`.".".`domainname`;
			$domain =~ s/[\r\n]+//g;
		}
	    
	    my($guess);
	                     
	        if( !$domain) {
	        	$guess = "";
	        } elsif ($Is_VMS && !$::Config{'d_socket'}) { 
	        	$guess = "$domain\:\:$me";
	        } else {
		    	$guess = "$me\@$domain" if $domain;
		    	$guess = "$me\@unknown.addresss" unless $domain;
			}
			
		$guess = $ENV{'REPLYTO'} if defined($ENV{'REPLYTO'});
		$guess = $ENV{"REPLY-TO"} if defined($ENV{'REPLY-TO'});
	
		if( $guess ) {
			paraprint <<EOF;


Your e-mail address will be useful if you need to be contacted. If the
default shown is not your full internet e-mail address, please correct it.

EOF
		} else {
			paraprint <<EOF;

So that you may be contacted if necessary, please enter 
your full internet e-mail address here.

EOF
		}
		print "Your address [$guess]: ";
	
		$from = <>;
		chop $from;
	
		if($from eq "") { $from = $guess }
	
	}
	
	#if( $from =~ /^(.*)\@(.*)$/ ) {
	#	$mailname = $1;
	#	$maildomain = $2;
	#}

	if( $from eq $cc or $me eq $cc ) {
		# Try not to copy ourselves
		$cc = "yourself";
	}


	# Prompt for administrator address, unless an override was given
	if( !$::opt_C and !$::opt_c ) {
		paraprint <<EOF;


A copy of this report can be sent to your local
perl administrator. If the address is wrong, please 
correct it, or enter 'none' or 'yourself' to not send
a copy.

EOF

		print "Local perl administrator [$cc]: ";
	
		my($entry) = scalar(<>);
		chop $entry;
	
		if($entry ne "") {
			$cc = $entry;
			if($me eq $cc) { $cc = "" }
		}
	
	}

	if($cc =~ /^(none|yourself|me|myself|ourselves)$/i) { $cc = "" }

	$andcc = " and $cc" if $cc;

editor:
	
	# Prompt for editor, if no override is given
	if(! $::opt_e and ! $::opt_f and ! $::opt_b) {
		paraprint <<EOF;


Now you need to supply the bug report. Try to make
the report concise but descriptive. Include any 
relevant detail. If you are reporting something
that does not work as you think it should, please
try to include example of both the actual 
result, and what you expected.

Some information about your local
perl configuration will automatically be included 
at the end of the report. If you are using any
unusual version of perl, please try and confirm
exactly which versions are relevant.

You will probably want to use an editor to enter
the report. If "$ed" is the editor you want
to use, then just press Enter, otherwise type in
the name of the editor you would like to use.

If you would like to use a prepared file, type
"file", and you will be asked for the filename.

EOF

		print "Editor [$ed]: ";
	
		my($entry) =scalar(<>);
		chop $entry;
		
		$usefile = 0;
		if($entry eq "file") {
			$usefile = 1;
		} elsif($entry ne "") {
			$ed = $entry;
		} 
	}


	# Generate scratch file to edit report in
	
	{
	my($dir) = ($Is_VMS ? 'sys$scratch:' :
		    ($Is_MSWin32 and $ENV{'TEMP'} ? $ENV{'TEMP'} : '/tmp/'));
	$filename = "bugrep0$$";
	$filename++ while -e "$dir$filename";
	$filename = "$dir$filename";
	}
	
	
	# Prompt for file to read report from, if needed
	
	if( $usefile and ! $file) {
filename:
		paraprint <<EOF;

What is the name of the file that contains your report?

EOF

		print "Filename: ";
	
		my($entry) = scalar(<>);
		chop($entry);

		if($entry eq "") {
			paraprint <<EOF;
			
No filename? I'll let you go back and choose an editor again.			

EOF
			goto editor;
		}
		
		if(!-f $entry or !-r $entry) {
			paraprint <<EOF;
			
I'm sorry, but I can't read from `$entry'. Maybe you mistyped the name of
the file? If you don't want to send a file, just enter a blank line and you
can get back to the editor selection.

EOF
			goto filename;
		}
		$file = $entry;

	}


	# Generate report

	open(REP,">$filename");

	print REP <<EOF;
This is a bug report for perl from $from,
generated with the help of perlbug $Version running under perl $].

EOF

	if($body) {
		print REP $body;
	} elsif($usefile) {
		open(F,"<$file") or die "Unable to read report file from `$file': $!\n";
		while(<F>) {
		print REP $_
		}
		close(F);
	} else {
		print REP <<EOF;

-----------------------------------------------------------------
[Please enter your report here]



[Please do not change anything below this line]
-----------------------------------------------------------------
EOF
	}
	
	Dump(*REP);
	close(REP);

	# read in the report template once so that
	# we can track whether the user does any editing.
	# yes, *all* whitespace is ignored.
        open(REP, "<$filename");
        while (<REP>) {
		s/\s+//g;
		$REP{$_}++;
	}
	close(REP);

}

sub Dump {
	local(*OUT) = @_;
	
	print OUT <<EOF;

---
Site configuration information for perl $]:

EOF

	if( $::Config{cf_by} and $::Config{cf_time}) {
		print OUT "Configured by $::Config{cf_by} at $::Config{cf_time}.\n\n";
	}

	print OUT Config::myconfig;

	if($verbose) {
		print OUT "\nComplete configuration data for perl $]:\n\n";
		my($value);
		foreach (sort keys %::Config) {
			$value = $::Config{$_};
			$value =~ s/'/\\'/g;
			print OUT "$_='$value'\n";
		}
	}
	print OUT <<EOF;

---
\@INC for perl $]:
EOF
        for my $i (@INC) {
	    print OUT "\t$i\n";
        }

	print OUT <<EOF;

---
Environment for perl $]:
EOF
        for my $env (qw(PATH LD_LIBRARY_PATH),
		     sort grep { /^(?:PERL|LC_)/ } keys %ENV,
		     qw(LANG PERL_BADLANG
			SHELL HOME LOGDIR)) {
	    print OUT "    $env",
                      exists $ENV{$env} ? "=$ENV{$env}" : ' (unset)',
	              "\n";
	}
}

sub Edit {
	# Edit the report

	if($usefile) {
		$usefile = 0;
		paraprint <<EOF;

Please make sure that the name of the editor you want to use is correct.

EOF
		print "Editor [$ed]: ";
		
		my($entry) =scalar(<>);
		chop $entry;
	
		if($entry ne "") {
			$ed = $entry;
		} 
	}
	
tryagain:
	if(!$usefile and !$body) {
		my $sts = system("$ed $filename");
		if($sts) {
			#print "\nUnable to run editor!\n";
			paraprint <<EOF;

The editor you chose (`$ed') could apparently not be run!
Did you mistype the name of your editor? If so, please
correct it here, otherwise just press Enter. 

EOF
			print "Editor [$ed]: ";
		
			my($entry) =scalar(<>);
			chop $entry;
	
			if($entry ne "") {
				$ed = $entry;
				goto tryagain;
			} else {
			
			paraprint <<EOF;

You may want to save your report to a file, so you can edit and mail it
yourself.
EOF
			}
		} 
	}

        # Check that we have a report that has some, eh, report in it.

        my $unseen = 0;

        open(REP, "<$filename");
	# a strange way to check whether any significant editing
	# have been done: check whether any new non-empty lines
	# have been added. Yes, the below code ignores *any* space
	# in *any* line.
        while (<REP>) {
	    s/\s+//g;
	    $unseen++ if ($_ ne '' and not exists $REP{$_});
	}

	while ($unseen == 0) {
	    paraprint <<EOF;

I am sorry but it looks like you did not report anything.

EOF
		print "Action (Retry Edit/Cancel) ";
		my ($action) = scalar(<>);
		if ($action =~ /^[re]/i) { # <R>etry <E>dit
			goto tryagain;
		} elsif ($action =~ /^[cq]/i) { # <C>ancel, <Q>uit
		        Cancel();
		}
        }

}

sub Cancel {
    1 while unlink($filename);  # remove all versions under VMS
    print "\nCancelling.\n";
    exit(0);
}

sub NowWhat {

	# Report is done, prompt for further action
	if( !$::opt_S ) {
		while(1) {

			paraprint <<EOF;


Now that you have completed your report, would you like to send 
the message to $address$andcc, display the message on 
the screen, re-edit it, or cancel without sending anything?
You may also save the message as a file to mail at another time.

EOF

			print "Action (Send/Display/Edit/Cancel/Save to File): ";
			my($action) = scalar(<>);
			chop $action;

			if( $action =~ /^(f|sa)/i ) { # <F>ile/<Sa>ve
				print "\n\nName of file to save message in [perlbug.rep]: ";
				my($file) = scalar(<>);
				chop $file;
				if($file eq "") { $file = "perlbug.rep" }
			
				open(FILE,">$file");
				open(REP,"<$filename");
				print FILE "To: $address\nSubject: $subject\n";
				print FILE "Cc: $cc\n" if $cc;
				print FILE "Reply-To: $from\n" if $from;
				print FILE "\n";
				while(<REP>) { print FILE }
				close(REP);
				close(FILE);
	
				print "\nMessage saved in `$file'.\n";
				exit;

			} elsif( $action =~ /^(d|l|sh)/i ) { # <D>isplay, <L>ist, <Sh>ow
				# Display the message
				open(REP,"<$filename");
				while(<REP>) { print $_ }
				close(REP);
			} elsif( $action =~ /^se/i ) { # <S>end
				# Send the message
				print "\
Are you certain you want to send this message?
Please type \"yes\" if you are: ";
				my($reply) = scalar(<STDIN>);
				chop($reply);
				if( $reply eq "yes" ) {
					last;
				} else {
					paraprint <<EOF;

That wasn't a clear "yes", so I won't send your message. If you are sure
your message should be sent, type in "yes" (without the quotes) at the
confirmation prompt.

EOF
					
				}
			} elsif( $action =~ /^[er]/i ) { # <E>dit, <R>e-edit
				# edit the message
				Edit();
				#system("$ed $filename");
			} elsif( $action =~ /^[qc]/i ) { # <C>ancel, <Q>uit
			        Cancel();
			} elsif( $action =~ /^s/ ) {
				paraprint <<EOF;

I'm sorry, but I didn't understand that. Please type "send" or "save".
EOF
			}
		
		}
	}
}


sub Send {

	# Message has been accepted for transmission -- Send the message
	
	if($::HaveSend) {

		$msg = new Mail::Send Subject => $subject, To => $address;
	
		$msg->cc($cc) if $cc;
		$msg->add("Reply-To",$from) if $from;
	    
		$fh = $msg->open;

		open(REP,"<$filename");
		while(<REP>) { print $fh $_ }
		close(REP);
	
		$fh->close;  
	
	} else {
		if ($Is_VMS) {
			if ( ($address =~ /@/ and $address !~ /^\w+%"/) or
			     ($cc      =~ /@/ and $cc      !~ /^\w+%"/) ){
				my($prefix);
				foreach (qw[ IN MX SMTP UCX PONY WINS ],'') {
					$prefix = "$_%",last if $ENV{"MAIL\$PROTOCOL_$_"};
				}
				$address = qq[${prefix}"$address"] unless $address =~ /^\w+%"/;
				$cc = qq[${prefix}"$cc"] unless !$cc || $cc =~ /^\w+%"/;
			}
			$subject =~ s/"/""/g; $address =~ s/"/""/g; $cc =~ s/"/""/g;
			my($sts) = system(qq[mail/Subject="$subject" $filename. "$address","$cc"]);
			if ($sts) { die "Can't spawn off mail\n\t(leaving bug report in $filename): $sts\n;" }
		} else {
			my($sendmail) = "";
			
			foreach (qw(/usr/lib/sendmail /usr/sbin/sendmail /usr/ucblib/sendmail))
			{
				$sendmail = $_, last if -e $_;
			}
			
			paraprint <<"EOF" and die "\n" if $sendmail eq "";
			
I am terribly sorry, but I cannot find sendmail, or a close equivalent, and
the perl package Mail::Send has not been installed, so I can't send your bug
report. We apologize for the inconvenience.

So you may attempt to find some way of sending your message, it has
been left in the file `$filename'.

EOF
			
			open(SENDMAIL,"|$sendmail -t");
			print SENDMAIL "To: $address\n";
			print SENDMAIL "Subject: $subject\n";
			print SENDMAIL "Cc: $cc\n" if $cc;
			print SENDMAIL "Reply-To: $from\n" if $from;
			print SENDMAIL "\n\n";
			open(REP,"<$filename");
			while(<REP>) { print SENDMAIL $_ }
			close(REP);
			
			close(SENDMAIL);
		}
	
	}
	
	print "\nMessage sent.\n";

	1 while unlink($filename);  # remove all versions under VMS

}

sub Help {
	print <<EOF; 

A program to help generate bug reports about perl5, and mail them. 
It is designed to be used interactively. Normally no arguments will
be needed.
	
Usage:
$0  [-v] [-a address] [-s subject] [-b body | -f file ]
    [-r returnaddress] [-e editor] [-c adminaddress | -C] [-S] [-t] [-h]
    
Simplest usage:  run "$0", and follow the prompts.

Options:

  -v    Include Verbose configuration data in the report
  -f    File containing the body of the report. Use this to 
        quickly send a prepared message.
  -S    Send without asking for confirmation.
  -a    Address to send the report to. Defaults to `$address'.
  -c    Address to send copy of report to. Defaults to `$cc'.
  -C    Don't send copy to administrator.
  -s    Subject to include with the message. You will be prompted 
        if you don't supply one on the command line.
  -b    Body of the report. If not included on the command line, or
        in a file with -f, you will get a chance to edit the message.
  -r    Your return address. The program will ask you to confirm
        this if you don't give it here.
  -e    Editor to use. 
  -t    Test mode. The target address defaults to `$testaddress'.
  -d	Data mode (the default if you redirect or pipe output.) 
        This prints out your configuration data, without mailing
        anything. You can use this with -v to get more complete data.
  -h    Print this help message. 
  
EOF
}

sub paraprint {
    my @paragraphs = split /\n{2,}/, "@_";
    print "\n\n";
    for (@paragraphs) {   # implicit local $_
    	s/(\S)\s*\n/$1 /g;
	    write;
	    print "\n";
    }
                       
}
                            

format STDOUT =
^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< ~~
$_
.

__END__

=head1 NAME

perlbug - how to submit bug reports on Perl

=head1 SYNOPSIS

B<perlbug> S<[ B<-v> ]> S<[ B<-a> I<address> ]> S<[ B<-s> I<subject> ]>
S<[ B<-b> I<body> | B<-f> I<file> ]> S<[ B<-r> I<returnaddress> ]>
S<[ B<-e> I<editor> ]> S<[ B<-c> I<adminaddress> | B<-C> ]>
S<[ B<-S> ]> S<[ B<-t> ]>  S<[ B<-d> ]>  S<[ B<-h> ]>

=head1 DESCRIPTION

A program to help generate bug reports about perl or the modules that
come with it, and mail them. 

If you have found a bug with a non-standard port (one that was not part
of the I<standard distribution>), a binary distribution, or a
non-standard module (such as Tk, CGI, etc), then please see the
documentation that came with that distribution to determine the correct
place to report bugs.

C<perlbug> is designed to be used interactively. Normally no arguments
will be needed.  Simply run it, and follow the prompts.

If you are unable to run B<perlbug> (most likely because you don't have
a working setup to send mail that perlbug recognizes), you may have to
compose your own report, and email it to B<perlbug@perl.com>.  You might
find the B<-d> option useful to get summary information in that case.

In any case, when reporting a bug, please make sure you have run through
this checklist:

=over 4

=item What version of perl you are running?

Type C<perl -v> at the command line to find out.

=item Are you running the latest released version of perl?

Look at http://www.perl.com/ to find out.  If it is not the latest
released version, get that one and see whether your bug has been
fixed.  Note that bug reports about old versions of perl, especially
those prior to the 5.0 release, are likely to fall upon deaf ears.
You are on your own if you continue to use perl1 .. perl4.

=item Are you sure what you have is a bug?

A significant number of the bug reports we get turn out to be documented
features in perl.  Make sure the behavior you are witnessing doesn't fall
under that category, by glancing through the documentation that comes
with perl (we'll admit this is no mean task, given the sheer volume of
it all, but at least have a look at the sections that I<seem> relevant).

Be aware of the familiar traps that perl programmers of various hues
fall into.  See L<perltrap>.

Try to study the problem under the perl debugger, if necessary.
See L<perldebug>.

=item Do you have a proper test case?

The easier it is to reproduce your bug, the more likely it will be
fixed, because if no one can duplicate the problem, no one can fix it.
A good test case has most of these attributes: fewest possible number
of lines; few dependencies on external commands, modules, or
libraries; runs on most platforms unimpeded; and is self-documenting.

A good test case is almost always a good candidate to be on the perl
test suite.  If you have the time, consider making your test case so
that it will readily fit into the standard test suite.

=item Can you describe the bug in plain English?

The easier it is to understand a reproducible bug, the more likely it
will be fixed.  Anything you can provide by way of insight into the
problem helps a great deal.  In other words, try to analyse the
problem to the extent you feel qualified and report your discoveries.

=item Can you fix the bug yourself?

A bug report which I<includes a patch to fix it> will almost
definitely be fixed.  Use the C<diff> program to generate your patches
(C<diff> is being maintained by the GNU folks as part of the B<diffutils>
package, so you should be able to get it from any of the GNU software
repositories).  If you do submit a patch, the cool-dude counter at
perlbug@perl.com will register you as a savior of the world.  Your
patch may be returned with requests for changes, or requests for more
detailed explanations about your fix.

Here are some clues for creating quality patches: Use the B<-c> or
B<-u> switches to the diff program (to create a so-called context or
unified diff).  Make sure the patch is not reversed (the first
argument to diff is typically the original file, the second argument
your changed file).  Make sure you test your patch by applying it with
the C<patch> program before you send it on its way.  Try to follow the
same style as the code you are trying to patch.  Make sure your patch
really does work (C<make test>, if the thing you're patching supports
it).

=item Can you use C<perlbug> to submit the report?

B<perlbug> will, amongst other things, ensure your report includes
crucial information about your version of perl.  If C<perlbug> is unable
to mail your report after you have typed it in, you may have to compose
the message yourself, add the output produced by C<perlbug -d> and email
it to B<perlbug@perl.com>.  If, for some reason, you cannot run
C<perlbug> at all on your system, be sure to include the entire output
produced by running C<perl -V> (note the uppercase V).

=back

Having done your bit, please be prepared to wait, to be told the bug
is in your code, or even to get no reply at all.  The perl maintainers
are busy folks, so if your problem is a small one or if it is
difficult to understand, they may not respond with a personal reply.
If it is important to you that your bug be fixed, do monitor the
C<Changes> file in any development releases since the time you submitted
the bug, and encourage the maintainers with kind words (but never any
flames!).  Feel free to resend your bug report if the next released
version of perl comes out and your bug is still present.

=head1 OPTIONS

=over 8

=item B<-a>

Address to send the report to.  Defaults to `perlbug@perl.com'.

=item B<-b>

Body of the report.  If not included on the command line, or
in a file with B<-f>, you will get a chance to edit the message.

=item B<-C>

Don't send copy to administrator.

=item B<-c>

Address to send copy of report to.  Defaults to the address of the
local perl administrator (recorded when perl was built).

=item B<-d>

Data mode (the default if you redirect or pipe output).  This prints out
your configuration data, without mailing anything.  You can use this
with B<-v> to get more complete data.

=item B<-e>

Editor to use. 

=item B<-f>

File containing the body of the report.  Use this to quickly send a
prepared message.

=item B<-h>

Prints a brief summary of the options.

=item B<-r>

Your return address.  The program will ask you to confirm its default
if you don't use this option.

=item B<-S>

Send without asking for confirmation.

=item B<-s>

Subject to include with the message.  You will be prompted if you don't
supply one on the command line.

=item B<-t>

Test mode.  The target address defaults to `perlbug-test@perl.com'.

=item B<-v>

Include verbose configuration data in the report.

=back

=head1 AUTHORS

Kenneth Albanowski (E<lt>kjahds@kjahds.comE<gt>), subsequently I<doc>tored
by Gurusamy Sarathy (E<lt>gsar@umich.eduE<gt>), Tom Christiansen
(E<lt>tchrist@perl.comE<gt>), and Nathan Torkington
(E<lt>gnat@frii.comE<gt>).

=head1 SEE ALSO

perl(1), perldebug(1), perltrap(1), diff(1), patch(1)

=head1 BUGS

None known (guess what must have been used to report them?)

=cut

!NO!SUBS!

close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';

