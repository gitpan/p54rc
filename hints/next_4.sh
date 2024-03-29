######################################################################
#
# IMPORTANT: before you run 'make', you need to enter one of these two
# lines (depending on your shell):
#	 DYLD_LIBRARY_PATH=`pwd`; export DYLD_LIBRARY_PATH
# or
#	setenv DYLD_LIBRARY_PATH `pwd`
#
######################################################################

# Posix support has been removed from NextStep 
#
useposix='undef'

libpth='/lib /usr/lib'
libswanted=' '
libc='/NextLibrary/Frameworks/System.framework/System'

ldflags='-dynamic -prebind'
lddlflags='-dynamic -bundle -undefined suppress'
ccflags='-dynamic -fno-common -DUSE_NEXT_CTYPE -DUSE_PERL_SBRK -DHIDEMYMALLOC'
cccdlflags='none'
ld='cc'
#optimize='-g -O'

######################################################################
# MAB support
######################################################################
# By default we will build for all architectures your development
# environment supports. If you only want to build for the platform
# you are on, simply comment or remove the line below.
#
# If you want to build for specific architectures, change the line
# below to something like
#
#	archs=(m68k i386)
#
archs=`/bin/lipo -info /usr/lib/libm.a | sed 's/^[^:]*:[^:]*: //'`

#
# leave the following part alone
#
archcount=`echo $archs |wc -w`
if [ $archcount -gt 1 ]
then
	for d in $archs
	do
			mabflags="$mabflags -arch $d"
	done
	ccflags="$ccflags $mabflags"
	ldflags="$ldflags $mabflags"
	lddlflags="$lddlflags $mabflags"
fi
######################################################################
# END MAB support
######################################################################

useshprlib='true'
dlext='bundle'
so='dylib'

#
# The default prefix would be '/usr/local'. But since many people are
# likely to have still 3.3 machines on their network, we do not want
# to overwrite possibly existing 3.3 binaries. 
# You can use Configure -Dprefix=/foo/bar to override this, or simply
# remove the lines below.
#
case "$prefix" in
'') prefix='/usr/local/OPENSTEP' ;;
esac

archname='OPENSTEP-Mach'

#
# At least on m68k there are situations when memcmp doesn't behave
# as expected.  So we'll use perl's memcmp.
#
d_sanemcmp='undef'

d_strcoll='undef'
i_dbm='define'
i_utime='undef'
groupstype='int'
direntrytype='struct direct'

usemymalloc='y'
clocktype='int'

#
# On some NeXT machines, the timestamp put by ranlib is not correct, and
# this may cause useless recompiles.  Fix that by adding a sleep before
# running ranlib.  The '5' is an empirical number that's "long enough."
# (Thanks to Andreas Koenig <k@franz.ww.tu-berlin.de>)
ranlib='sleep 5; /bin/ranlib' 
