BEGIN{$CPAN::Suppress_readline=1 unless defined $CPAN::term;}

use CPAN;

$CPAN::META->hasMD5(0);
$CPAN::META->hasLWP(0);
@EXPORT = @CPAN::EXPORT;

*AUTOLOAD = \&CPAN::AUTOLOAD;

=head1 NAME

CPAN::Nox - Wrapper around CPAN.pm without using any XS module

=head1 SYNOPSIS

Interactive mode:

  perl -MCPAN::Nox -e shell;

=head1 DESCRIPTION

This package has the same functionality as CPAN.pm, but tries to
prevent the usage of compiled extensions during it's own
execution. It's primary purpose is a rescue in case you upgraded perl
and broke binary compatibility somehow.

=head1  SEE ALSO

CPAN(3)

=cut

