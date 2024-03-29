#! /bin/sh
case $CONFIG in
'')
	if test -f config.sh; then TOP=.;
	elif test -f ../config.sh; then TOP=..;
	elif test -f ../../config.sh; then TOP=../..;
	elif test -f ../../../config.sh; then TOP=../../..;
	elif test -f ../../../../config.sh; then TOP=../../../..;
	else
		echo "Can't find config.sh."; exit 1
	fi
	. $TOP/config.sh
	;;
esac
: This forces SH files to create target in same directory as SH file.
: This is so that make depend always knows where to find SH derivatives.
case "$0" in
*/*) cd `expr X$0 : 'X\(.*\)/'` ;;
esac

case "$d_dosuid" in
*define*) suidperl='suidperl' ;;
*) suidperl='';;
esac

linklibperl='$(LIBPERL)'
shrpldflags='$(LDDLFLAGS)'
case "$useshrplib" in
true)
	pldlflags="$cccdlflags"
	# NeXT-4 specific stuff.  Can't we do this in the hint file?
	case "${osname}${osvers}" in
	next4*)
		ld=libtool
		lddlflags="-dynamic -undefined warning -framework System \
		-compatibility_version 1 -current_version $patchlevel \
		-prebind -seg1addr 0x27000000 -install_name \$(shrpdir)/\$@"
		;;
	sunos*|freebsd[23]*|netbsd*)
		linklibperl="-lperl"
		;;
	aix*)
		shrpldflags="-H512 -T512 -bhalt:4 -bM:SRE -bE:perl.exp"
		shrpldflags="$shrpldflags -b noentry $ldflags $libs $cryptlib"
		aixinstdir=`pwd | sed 's/\/UU$//'`
		linklibperl="-L $archlibexp/CORE -L $aixinstdir -lperl"
		;;
	esac
	;;
*)	pldlflags=''
	;;
esac

: Prepare dependency lists for Makefile.
dynamic_list=' '
for f in $dynamic_ext; do
    : the dependency named here will never exist
      base=`echo "$f" | sed 's/.*\///'`
    dynamic_list="$dynamic_list lib/auto/$f/$base.$dlext"
done

static_list=' '
for f in $static_ext; do
	base=`echo "$f" | sed 's/.*\///'`
	static_list="$static_list lib/auto/$f/$base\$(LIB_EXT)"
done

echo "Extracting Makefile (with variable substitutions)"
$spitshell >Makefile <<!GROK!THIS!
# Makefile.SH
# This file is derived from Makefile.SH.  Any changes made here will
# be lost the next time you run Configure.
#  Makefile is used to generate $firstmakefile.  The only difference
#  is that $firstmakefile has the dependencies filled in at the end.
#
#
# I now supply perly.c with the kits, so don't remake perly.c without byacc
BYACC = $byacc
CC = $cc
LD = $ld

LDFLAGS = $ldflags
CLDFLAGS = $ldflags

SMALL = $small
LARGE = $large $split
mallocsrc = $mallocsrc
mallocobj = $mallocobj
LNS = $lns
RMS = rm -f
ranlib = $ranlib

# The following are mentioned only to make metaconfig include the
# appropriate questions in Configure.  If you want to change these,
# edit config.sh instead, or specify --man1dir=/wherever on
# installman commandline.
bin = $installbin
scriptdir = $scriptdir
shrpdir = $archlibexp/CORE
privlib = $installprivlib
man1dir = $man1dir
man1ext = $man1ext
man3dir = $man3dir
man3ext = $man3ext

# The following are used to build and install shared libraries for
# dynamic loading.
LDDLFLAGS = $lddlflags
SHRPLDFLAGS = $shrpldflags
CCDLFLAGS = $ccdlflags
DLSUFFIX = .$dlext
PLDLFLAGS = $pldlflags
LIBPERL = $libperl
LLIBPERL= $linklibperl
SHRPENV = $shrpenv

dynamic_ext = $dynamic_list
static_ext = $static_list
ext = \$(dynamic_ext) \$(static_ext)
DYNALOADER = lib/auto/DynaLoader/DynaLoader\$(LIB_EXT)

libs = $libs $cryptlib

public = perl $suidperl utilities translators

shellflags = $shellflags

# This is set to  MAKE=$make if your $make command doesn't
# do it for you.
$make_set_make

# These variables will be used in a future version to make
# the make file more portable to non-unix systems.
AR = $ar
EXE_EXT = $exe_ext
LIB_EXT = $lib_ext
OBJ_EXT = $obj_ext
PATH_SEP = $path_sep

FIRSTMAKEFILE = $firstmakefile

# Any special object files needed by this architecture, e.g. os2/os2.obj
ARCHOBJS = $archobjs

.SUFFIXES: .c \$(OBJ_EXT)

# grrr
SHELL = $sh

!GROK!THIS!

## In the following dollars and backticks do not need the extra backslash.
$spitshell >>Makefile <<'!NO!SUBS!'

CCCMD = `sh $(shellflags) cflags $(LIBPERL) $@`

private = preplibrary lib/ExtUtils/Miniperl.pm lib/Config.pm

# Files to be built with variable substitution before miniperl
# is available.
sh = Makefile.SH cflags.SH config_h.SH makeaperl.SH makedepend.SH \
	makedir.SH perl_exp.SH writemain.SH

shextract = Makefile cflags config.h makeaperl makedepend \
	makedir perl.exp writemain

# Files to be built with variable substitution after miniperl is
# available.  Dependencies handled manually below (for now).

pl = pod/pod2html.PL pod/pod2latex.PL pod/pod2man.PL pod/pod2text.PL

plextract = pod/pod2html pod/pod2latex pod/pod2man pod/pod2text

addedbyconf = UU $(shextract) $(plextract) pstruct

h1 = EXTERN.h INTERN.h XSUB.h av.h config.h cop.h cv.h dosish.h
h2 = embed.h form.h gv.h handy.h hv.h keywords.h mg.h op.h
h3 = opcode.h patchlevel.h perl.h perly.h pp.h proto.h regcomp.h
h4 = regexp.h scope.h sv.h unixish.h util.h perlio.h
h = $(h1) $(h2) $(h3) $(h4)

c1 = $(mallocsrc) av.c scope.c op.c doop.c doio.c dump.c hv.c mg.c
c2 = perl.c perly.c pp.c pp_hot.c pp_ctl.c pp_sys.c regcomp.c regexec.c
c3 = gv.c sv.c taint.c toke.c util.c deb.c run.c universal.c globals.c perlio.c

c = $(c1) $(c2) $(c3) miniperlmain.c perlmain.c

obj1 = $(mallocobj) gv$(OBJ_EXT) toke$(OBJ_EXT) perly$(OBJ_EXT) op$(OBJ_EXT) regcomp$(OBJ_EXT) dump$(OBJ_EXT) util$(OBJ_EXT) mg$(OBJ_EXT)
obj2 = hv$(OBJ_EXT) av$(OBJ_EXT) run$(OBJ_EXT) pp_hot$(OBJ_EXT) sv$(OBJ_EXT) pp$(OBJ_EXT) scope$(OBJ_EXT) pp_ctl$(OBJ_EXT) pp_sys$(OBJ_EXT)
obj3 = doop$(OBJ_EXT) doio$(OBJ_EXT) regexec$(OBJ_EXT) taint$(OBJ_EXT) deb$(OBJ_EXT) universal$(OBJ_EXT) globals$(OBJ_EXT) perlio$(OBJ_EXT)

obj = $(obj1) $(obj2) $(obj3) $(ARCHOBJS)

# Once perl has been Configure'd and built ok you build different
# perl variants (Debugging, Embedded, Multiplicity etc) by saying:
#	make clean; make LIBPERL=libperl<type>.a
# where <type> is some combination of 'd' and(or) 'e' or 'm'.
# See cflags to understand how this works.
#
# This mechanism is getting clunky and might not even work any more.
# EMBEDDING is on by default, and MULTIPLICITY doesn't work.
#

lintflags = -hbvxac

.c$(OBJ_EXT):
	$(CCCMD) $(PLDLFLAGS) $*.c

all: $(FIRSTMAKEFILE) miniperl $(private) $(plextract) $(public) $(dynamic_ext)
	@echo " "; echo "	Everything is up to date."

translators:	miniperl lib/Config.pm FORCE
	@echo " "; echo "	Making x2p stuff"; cd x2p; $(MAKE) all

utilities:	miniperl lib/Config.pm FORCE
	@echo " "; echo "	Making utilities"; cd utils; $(MAKE) all


# This is now done by installman only if you actually want the man pages.
#	@echo " "; echo "	Making docs"; cd pod; $(MAKE) all;

# Phony target to force checking subdirectories.
# Apparently some makes require an action for the FORCE target.
FORCE:
	@sh -c true

miniperlmain$(OBJ_EXT): miniperlmain.c
	$(CCCMD) $(PLDLFLAGS) $*.c

perlmain.c: miniperlmain.c config.sh $(FIRSTMAKEFILE)
	sh writemain $(DYNALOADER) $(static_ext) > tmp
	sh mv-if-diff tmp perlmain.c

perlmain$(OBJ_EXT): perlmain.c
	$(CCCMD) $(PLDLFLAGS) $*.c

# The file ext.libs is a list of libraries that must be linked in
# for static extensions, e.g. -lm -lgdbm, etc.  The individual
# static extension Makefile's add to it.
ext.libs: $(static_ext)
	-@test -f ext.libs || touch ext.libs

!NO!SUBS!

# How to build libperl.  This is still rather convoluted.
# Load up custom Makefile.SH fragment for shared loading and executables:
if test -r $osname/Makefile.SHs ; then
	. $osname/Makefile.SHs
	$spitshell >>Makefile <<!GROK!THIS!

Makefile: $osname/Makefile.SHs
!GROK!THIS!
else
	$spitshell >>Makefile <<'!NO!SUBS!'
$(LIBPERL): $& perl$(OBJ_EXT) $(obj)
!NO!SUBS!
	case "$useshrplib" in
	true)
		$spitshell >>Makefile <<'!NO!SUBS!'
	$(LD) $(SHRPLDFLAGS) -o $@ perl$(OBJ_EXT) $(obj)
!NO!SUBS!
		case "$osname" in
		aix)
			$spitshell >>Makefile <<'!NO!SUBS!'
	mv $@ libperl$(OBJ_EXT)
	$(AR) qv $(LIBPERL) libperl$(OBJ_EXT)
!NO!SUBS!
			;;
		esac
		;;
	*)
		$spitshell >>Makefile <<'!NO!SUBS!'
	rm -f $(LIBPERL)
	$(AR) rcu $(LIBPERL) perl$(OBJ_EXT) $(obj)
	@$(ranlib) $(LIBPERL)
!NO!SUBS!
		;;
	esac
	$spitshell >>Makefile <<'!NO!SUBS!'

# How to build executables.

# The $& notation tells Sequent machines that it can do a parallel make,
# and is harmless otherwise.
# The miniperl -w -MExporter line is a basic cheap test to catch errors
# before make goes on to run preplibrary and then MakeMaker on extensions.
# This is very handy because later errors are often caused by miniperl
# build problems but that's not obvious to the novice.
# The Module used here must not depend on Config or any extensions.

miniperl: $& miniperlmain$(OBJ_EXT) $(LIBPERL)
	$(CC) $(LARGE) $(CLDFLAGS) -o miniperl miniperlmain$(OBJ_EXT) $(LLIBPERL) $(libs)
	@./miniperl -w -Ilib -MExporter -e 0 || $(MAKE) minitest

perl: $& perlmain$(OBJ_EXT) $(LIBPERL) $(DYNALOADER) $(static_ext) ext.libs
	$(SHRPENV) $(CC) $(LARGE) $(CLDFLAGS) $(CCDLFLAGS) -o perl perlmain$(OBJ_EXT) $(DYNALOADER) $(static_ext) $(LLIBPERL) `cat ext.libs` $(libs)

pureperl: $& perlmain$(OBJ_EXT) $(LIBPERL) $(DYNALOADER) $(static_ext) ext.libs
	purify $(CC) $(LARGE) $(CLDFLAGS) $(CCDLFLAGS) -o pureperl perlmain$(OBJ_EXT) $(DYNALOADER) $(static_ext) $(LLIBPERL) `cat ext.libs` $(libs)

purecovperl: $& perlmain$(OBJ_EXT) $(LIBPERL) $(DYNALOADER) $(static_ext) ext.libs
	purecov $(CC) $(LARGE) $(CLDFLAGS) $(CCDLFLAGS) -o purecovperl perlmain$(OBJ_EXT) $(DYNALOADER) $(static_ext) $(LLIBPERL) `cat ext.libs` $(libs)

quantperl: $& perlmain$(OBJ_EXT) $(LIBPERL) $(DYNALOADER) $(static_ext) ext.libs
	quantify $(CC) $(LARGE) $(CLDFLAGS) $(CCDLFLAGS) -o quantperl perlmain$(OBJ_EXT) $(DYNALOADER) $(static_ext) $(LLIBPERL) `cat ext.libs` $(libs)

# This version, if specified in Configure, does ONLY those scripts which need
# set-id emulation.  Suidperl must be setuid root.  It contains the "taint"
# checks as well as the special code to validate that the script in question
# has been invoked correctly.

suidperl: $& sperl$(OBJ_EXT) perlmain$(OBJ_EXT) $(LIBPERL) $(DYNALOADER) $(static_ext) ext.libs
	$(CC) $(LARGE) $(CLDFLAGS) $(CCDLFLAGS) -o suidperl perlmain$(OBJ_EXT) sperl$(OBJ_EXT) $(DYNALOADER) $(static_ext) $(LLIBPERL) `cat ext.libs` $(libs)

!NO!SUBS!

fi

$spitshell >>Makefile <<'!NO!SUBS!'

sperl$(OBJ_EXT): perl.c perly.h patchlevel.h $(h)
	$(RMS) sperl.c
	$(LNS) perl.c sperl.c
	$(CCCMD) -DIAMSUID sperl.c
	$(RMS) sperl.c

# We have to call our ./makedir because Ultrix 4.3 make can't handle the line
#	test -d lib/auto || mkdir lib/auto
#
preplibrary: miniperl lib/Config.pm $(plextract)
	@sh ./makedir lib/auto
	@echo "	AutoSplitting perl library"
	@./miniperl -Ilib -e 'use AutoSplit; \
		autosplit_lib_modules(@ARGV)' lib/*.pm lib/*/*.pm

# Take care to avoid modifying lib/Config.pm without reason
lib/Config.pm: config.sh miniperl configpm
	./miniperl configpm tmp
	sh mv-if-diff tmp lib/Config.pm

lib/ExtUtils/Miniperl.pm: miniperlmain.c miniperl minimod.pl lib/Config.pm
	./miniperl minimod.pl > tmp && mv tmp $@

$(plextract):	miniperl lib/Config.pm
	./miniperl -Ilib $@.PL

install: all install.perl install.man

install.perl:	all installperl
	./perl installperl

install.man:	all installman
	./perl installman

# Not implemented yet.
#install.html:	all installhtml
#	./perl installhtml

# I now supply perly.c with the kits, so the following section is
# used only if you force byacc to run by saying
# 	make run_byacc
# Since we patch up the byacc output, the perly.fixer script needs
# to run with precisely the same version of byacc as I use.  You
# normally shouldn't remake perly.[ch].

run_byacc:	FORCE
	@ echo 'Expect' 113 shift/reduce and 1 reduce/reduce conflict
	$(BYACC) -d perly.y
	sh $(shellflags) ./perly.fixer y.tab.c perly.c
	sed -e 's/fprintf *( *stderr *,/PerlIO_printf(Perl_debug_log,/g' \
	    -e 's/y\.tab/perly/g' perly.c >perly.tmp && mv perly.tmp perly.c
	echo 'extern YYSTYPE yylval;' >>y.tab.h
	cmp -s y.tab.h perly.h && rm -f y.tab.h || mv y.tab.h perly.h
	- perl vms/vms_yfix.pl perly.c perly.h vms/perly_c.vms vms/perly_h.vms

# We don't want to regenerate perly.c and perly.h, but they might
# appear out-of-date after a patch is applied or a new distribution is
# made.
perly.c: perly.y
	-@sh -c true

perly.h: perly.y
	-@sh -c true

# The following three header files are generated automatically
#	keywords.h:	keywords.pl
#	opcode.h:	opcode.pl
#	embed.h:  	embed.pl global.sym interp.sym
# The correct versions should be already supplied with the perl kit,
# in case you don't have perl available.
# To force them to run, type
#	make regen_headers
regen_headers:	FORCE
	perl keywords.pl
	perl opcode.pl
	perl embed.pl

# Extensions:
# Names added to $(dynamic_ext) or $(static_ext) will automatically
# get built.  There should ordinarily be no need to change any of
# this part of makefile.
#
# The dummy dependency is a place holder in case $(dynamic_ext) or
# $(static_ext) is empty.
#
# DynaLoader may be needed for extensions that use Makefile.PL.

$(DYNALOADER):	miniperl preplibrary FORCE
	@sh ext/util/make_ext static $@ LIBPERL_A=$(LIBPERL)

d_dummy $(dynamic_ext):	miniperl preplibrary $(DYNALOADER) FORCE
	@sh ext/util/make_ext dynamic $@ LIBPERL_A=$(LIBPERL)

s_dummy $(static_ext):	miniperl preplibrary $(DYNALOADER) FORCE
	@sh ext/util/make_ext static $@ LIBPERL_A=$(LIBPERL)

clean:		_tidy _mopup

realclean:	_cleaner _mopup
	@echo "Note that make realclean does not delete config.sh"

clobber:	_cleaner _mopup
	rm -f config.sh cppstdin

distclean:	clobber

# Do not 'make _mopup' directly.
_mopup:
	rm -f *$(OBJ_EXT) *$(LIB_EXT) all perlmain.c
	rm -f perl.exp ext.libs
	-rm -f perl.export perl.dll perl.libexp perl.map perl.def
	rm -f perl suidperl miniperl $(LIBPERL)

# Do not 'make _tidy' directly.
_tidy:
	-cd pod; $(MAKE) clean
	-cd utils; $(MAKE) clean
	-cd x2p; $(MAKE) clean
	-@for x in $(DYNALOADER) $(dynamic_ext) $(static_ext) ; do \
	sh ext/util/make_ext clean $$x ; \
	done

# Do not 'make _cleaner' directly.
_cleaner:
	-cd os2; rm -f Makefile
	-cd pod; $(MAKE) realclean
	-cd utils; $(MAKE) realclean
	-cd x2p; $(MAKE) realclean
	-@for x in $(DYNALOADER) $(dynamic_ext) $(static_ext) ; do \
	sh ext/util/make_ext realclean $$x ; \
	done
	rm -f *.orig */*.orig *~ */*~ core t/core t/c t/perl
	rm -rf $(addedbyconf)
	rm -f $(FIRSTMAKEFILE) $(FIRSTMAKEFILE).old
	rm -f $(private)
	rm -rf lib/auto
	rm -f lib/.exists
	rm -f h2ph.man pstruct
	rm -rf .config

# The following lint has practically everything turned on.  Unfortunately,
# you have to wade through a lot of mumbo jumbo that can't be suppressed.
# If the source file has a /*NOSTRICT*/ somewhere, ignore the lint message
# for that spot.

lint: perly.c $(c)
	lint $(lintflags) $(defs) perly.c $(c) > perl.fuzz

# Need to unset during recursion to go out of loop

MAKEDEPEND = makedepend

$(FIRSTMAKEFILE):	Makefile $(MAKEDEPEND)
	$(MAKE) depend MAKEDEPEND=

config.h: config_h.SH config.sh
	$(SHELL) config_h.SH

perl.exp: perl_exp.SH config.sh
	$(SHELL) perl_exp.SH

# When done, touch perlmain.c so that it doesn't get remade each time.
depend: makedepend
	sh ./makedepend
	- test -s perlmain.c && touch perlmain.c
	cd x2p; $(MAKE) depend

# Cannot postpone this until $firstmakefile is ready ;-)
makedepend: makedepend.SH config.sh
	sh ./makedepend.SH

check test: miniperl perl preplibrary $(dynamic_ext)
	- cd t && (rm -f perl$(EXE_EXT); $(LNS) ../perl$(EXE_EXT) perl$(EXE_EXT)) && ./perl TEST </dev/tty

# Can't depend on lib/Config.pm because that might be where miniperl
# is crashing.
minitest: miniperl
	@echo "You may see some irrelevant test failures if you have been unable"
	@echo "to build lib/Config.pm."
	- cd t && (rm -f perl$(EXE_EXT); $(LNS) ../miniperl$(EXE_EXT) perl$(EXE_EXT)) \
		&& ./perl TEST base/*.t comp/*.t cmd/*.t io/*.t op/*.t pragma/*.t </dev/tty

clist:	$(c)
	echo $(c) | tr ' ' '\012' >.clist

hlist:  $(h)
	echo $(h) | tr ' ' '\012' >.hlist

shlist: $(sh)
	echo $(sh) | tr ' ' '\012' >.shlist

pllist: $(pl)
	echo $(pl) | tr ' ' '\012' >.pllist

Makefile: Makefile.SH ./config.sh
	$(SHELL) Makefile.SH

distcheck: FORCE
	perl '-MExtUtils::Manifest=&fullcheck' -e 'fullcheck()'

# AUTOMATICALLY GENERATED MAKE DEPENDENCIES--PUT NOTHING BELOW THIS LINE
# If this runs make out of memory, delete /usr/include lines.
!NO!SUBS!

$eunicefix Makefile
case `pwd` in
*SH)
    $rm -f ../Makefile
    $ln Makefile ../Makefile
    ;;
esac
$rm -f $firstmakefile
