package ExtUtils::Mksymlists;
use strict qw[ subs refs ];
# no strict 'vars';  # until filehandles are exempted

use Carp;
use Exporter;
use vars qw( @ISA @EXPORT $VERSION );
@ISA = 'Exporter';
@EXPORT = '&Mksymlists';
$VERSION = substr q$Revision: 1.13 $, 10;

sub Mksymlists {
    my(%spec) = @_;
    my($osname) = $^O;

    croak("Insufficient information specified to Mksymlists")
        unless ( $spec{NAME} or
                 ($spec{FILE} and ($spec{DL_FUNCS} or $spec{FUNCLIST})) );

    $spec{DL_VARS} = [] unless $spec{DL_VARS};
    ($spec{FILE} = $spec{NAME}) =~ s/.*::// unless $spec{FILE};
    $spec{DL_FUNCS} = { $spec{NAME} => [] }
        unless ( ($spec{DL_FUNCS} and keys %{$spec{DL_FUNCS}}) or
                 $spec{FUNCLIST});
    $spec{FUNCLIST} = [] unless $spec{FUNCLIST};
    if (defined $spec{DL_FUNCS}) {
        my($package);
        foreach $package (keys %{$spec{DL_FUNCS}}) {
            my($packprefix,$sym,$bootseen);
            ($packprefix = $package) =~ s/\W/_/g;
            foreach $sym (@{$spec{DL_FUNCS}->{$package}}) {
                if ($sym =~ /^boot_/) {
                    push(@{$spec{FUNCLIST}},$sym);
                    $bootseen++;
                }
                else { push(@{$spec{FUNCLIST}},"XS_${packprefix}_$sym"); }
            }
            push(@{$spec{FUNCLIST}},"boot_$packprefix") unless $bootseen;
        }
    }

#    We'll need this if we ever add any OS which uses mod2fname
#    not as pseudo-builtin.
#    require DynaLoader;
    if (defined &DynaLoader::mod2fname and not $spec{DLBASE}) {
        $spec{DLBASE} = DynaLoader::mod2fname([ split(/::/,$spec{NAME}) ]);
    }

    if    ($osname eq 'aix') { _write_aix(\%spec); }
    elsif ($osname eq 'VMS') { _write_vms(\%spec) }
    elsif ($osname eq 'os2') { _write_os2(\%spec) }
    elsif ($osname eq 'MSWin32') { _write_win32(\%spec) }
    else { croak("Don't know how to create linker option file for $osname\n"); }
}


sub _write_aix {
    my($data) = @_;

    rename "$data->{FILE}.exp", "$data->{FILE}.exp_old";

    open(EXP,">$data->{FILE}.exp")
        or croak("Can't create $data->{FILE}.exp: $!\n");
    print EXP join("\n",@{$data->{DL_VARS}}, "\n") if @{$data->{DL_VARS}};
    print EXP join("\n",@{$data->{FUNCLIST}}, "\n") if @{$data->{FUNCLIST}};
    close EXP;
}


sub _write_os2 {
    my($data) = @_;

    if (not $data->{DLBASE}) {
        ($data->{DLBASE} = $data->{NAME}) =~ s/.*:://;
        $data->{DLBASE} = substr($data->{DLBASE},0,7) . '_';
    }
    rename "$data->{FILE}.def", "$data->{FILE}_def.old";

    open(DEF,">$data->{FILE}.def")
        or croak("Can't create $data->{FILE}.def: $!\n");
    print DEF "LIBRARY '$data->{DLBASE}' INITINSTANCE TERMINSTANCE\n";
    print DEF "CODE LOADONCALL\n";
    print DEF "DATA LOADONCALL NONSHARED MULTIPLE\n";
    print DEF "EXPORTS\n  ";
    print DEF join("\n  ",@{$data->{DL_VARS}}, "\n") if @{$data->{DL_VARS}};
    print DEF join("\n  ",@{$data->{FUNCLIST}}, "\n") if @{$data->{FUNCLIST}};
    if (%{$data->{IMPORTS}}) {
        print DEF "IMPORTS\n";
my ($name, $exp);
while (($name, $exp)= each %{$data->{IMPORTS}}) {
  print DEF "  $name=$exp\n";
}
    }
    close DEF;
}

sub _write_win32 {
    my($data) = @_;

    if (not $data->{DLBASE}) {
        ($data->{DLBASE} = $data->{NAME}) =~ s/.*:://;
        $data->{DLBASE} = substr($data->{DLBASE},0,7) . '_';
    }
    rename "$data->{FILE}.def", "$data->{FILE}_def.old";

    open(DEF,">$data->{FILE}.def")
        or croak("Can't create $data->{FILE}.def: $!\n");
    print DEF "LIBRARY $data->{DLBASE}\n";
    print DEF "CODE LOADONCALL\n";
    print DEF "DATA LOADONCALL NONSHARED MULTIPLE\n";
    print DEF "EXPORTS\n  ";
    print DEF join("\n  ",@{$data->{DL_VARS}}, "\n") if @{$data->{DL_VARS}};
    print DEF join("\n  ",@{$data->{FUNCLIST}}, "\n") if @{$data->{FUNCLIST}};
    if (%{$data->{IMPORTS}}) {
        print DEF "IMPORTS\n";
        my ($name, $exp);
        while (($name, $exp)= each %{$data->{IMPORTS}}) {
            print DEF "  $name=$exp\n";
        }
    }
    close DEF;
}


sub _write_vms {
    my($data) = @_;

    require Config; # a reminder for once we do $^O
    require ExtUtils::XSSymSet;

    my($isvax) = $Config::Config{'arch'} =~ /VAX/i;
    my($set) = new ExtUtils::XSSymSet;
    my($sym);

    rename "$data->{FILE}.opt", "$data->{FILE}.opt_old";

    open(OPT,">$data->{FILE}.opt")
        or croak("Can't create $data->{FILE}.opt: $!\n");

    # Options file declaring universal symbols
    # Used when linking shareable image for dynamic extension,
    # or when linking PerlShr into which we've added this package
    # as a static extension
    # We don't do anything to preserve order, so we won't relax
    # the GSMATCH criteria for a dynamic extension

    foreach $sym (@{$data->{FUNCLIST}}) {
        my $safe = $set->addsym($sym);
        if ($isvax) { print OPT "UNIVERSAL=$safe\n" }
        else        { print OPT "SYMBOL_VECTOR=($safe=PROCEDURE)\n"; }
    }
    foreach $sym (@{$data->{DL_VARS}}) {
        my $safe = $set->addsym($sym);
        print OPT "PSECT_ATTR=${sym},PIC,OVR,RD,NOEXE,WRT,NOSHR\n";
        if ($isvax) { print OPT "UNIVERSAL=$safe\n" }
        else        { print OPT "SYMBOL_VECTOR=($safe=DATA)\n"; }
    }
    close OPT;

    # Options file specifying RTLs to which this extension must be linked.
    # Eventually, the list of libraries will be supplied by a working
    # extliblist routine.
    open OPT,'>rtls.opt';
    print OPT "PerlShr/Share\n";
    foreach $rtl (split(/\s+/,$Config::Config{'libs'})) { print OPT "$rtl\n"; }
    close OPT;
}

1;

__END__

=head1 NAME

ExtUtils::Mksymlists - write linker options files for dynamic extension

=head1 SYNOPSIS

    use ExtUtils::Mksymlists;
    Mksymlists({ NAME     => $name ,
                 DL_VARS  => [ $var1, $var2, $var3 ],
                 DL_FUNCS => { $pkg1 => [ $func1, $func2 ],
                               $pkg2 => [ $func3 ] });

=head1 DESCRIPTION

C<ExtUtils::Mksymlists> produces files used by the linker under some OSs
during the creation of shared libraries for dynamic extensions.  It is
normally called from a MakeMaker-generated Makefile when the extension
is built.  The linker option file is generated by calling the function
C<Mksymlists>, which is exported by default from C<ExtUtils::Mksymlists>.
It takes one argument, a list of key-value pairs, in which the following
keys are recognized:

=over

=item NAME

This gives the name of the extension (I<e.g.> Tk::Canvas) for which
the linker option file will be produced.

=item DL_FUNCS

This is identical to the DL_FUNCS attribute available via MakeMaker,
from which it is usually taken.  Its value is a reference to an
associative array, in which each key is the name of a package, and
each value is an a reference to an array of function names which
should be exported by the extension.  For instance, one might say
C<DL_FUNCS =E<gt> { Homer::Iliad   =E<gt> [ qw(trojans greeks) ],
Homer::Odyssey =E<gt> [ qw(travellers family suitors) ] }>.  The
function names should be identical to those in the XSUB code;
C<Mksymlists> will alter the names written to the linker option
file to match the changes made by F<xsubpp>.  In addition, if
none of the functions in a list begin with the string B<boot_>,
C<Mksymlists> will add a bootstrap function for that package,
just as xsubpp does.  (If a B<boot_E<lt>pkgE<gt>> function is
present in the list, it is passed through unchanged.)  If
DL_FUNCS is not specified, it defaults to the bootstrap
function for the extension specified in NAME.

=item DL_VARS

This is identical to the DL_VARS attribute available via MakeMaker,
and, like DL_FUNCS, it is usually specified via MakeMaker.  Its
value is a reference to an array of variable names which should
be exported by the extension.

=item FILE

This key can be used to specify the name of the linker option file
(minus the OS-specific extension), if for some reason you do not
want to use the default value, which is the last word of the NAME
attribute (I<e.g.> for Tk::Canvas, FILE defaults to 'Canvas').

=item FUNCLIST

This provides an alternate means to specify function names to be
exported from the extension.  Its value is a reference to an
array of function names to be exported by the extension.  These
names are passed through unaltered to the linker options file.

=item DLBASE

This item specifies the name by which the linker knows the
extension, which may be different from the name of the
extension itself (for instance, some linkers add an '_' to the
name of the extension).  If it is not specified, it is derived
from the NAME attribute.  It is presently used only by OS2.

=back

When calling C<Mksymlists>, one should always specify the NAME
attribute.  In most cases, this is all that's necessary.  In
the case of unusual extensions, however, the other attributes
can be used to provide additional information to the linker.

=head1 AUTHOR

Charles Bailey I<E<lt>bailey@genetics.upenn.eduE<gt>>

=head1 REVISION

Last revised 14-Feb-1996, for Perl 5.002.
