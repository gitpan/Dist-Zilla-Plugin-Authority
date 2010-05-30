use strict;
use warnings;

# Smart loading of tests
my $numtests;
BEGIN {
	$numtests = 1;

	eval "use Test::NoWarnings";
	if ( ! $@ ) {
		# increment by one
		$numtests++;

	}
}

use Test::More tests => $numtests;

my $v = "\n";

eval {                     # no excuses!
    my $pv = ($^V || $]);
    $v .= "perl: $pv on $^O from $^X\n\n";     # report our Perl details
};

# Now, our module version dependencies:
sub pmver {
    my ($module,$wanted) = @_;
    $wanted = " (want $wanted)";
    my $pmver;
    eval "require $module;";
    if ($@) {
        if ($@ =~ m/Can't locate .* in \@INC/) {
            $pmver = 'module not found.';
        } else {
            diag("${module}: $@");
            $pmver = 'died during require.';
        }
    } else {
        my $version;
        eval { $version = $module->VERSION; };
        if ($@) {
            diag("${module}: $@");
            $pmver = 'died during VERSION check.';
        } elsif (defined $version) {
            $pmver = "$version";
        } else {
            $pmver = '<undef>';
        }
    }

    # So, we should be good, right?
    return sprintf('%-40s => %-10s%-15s%s', $module, $pmver, $wanted, "\n");
}

eval { $v .= pmver('Dist::Zilla::Role::FileFinderUser','2.101170') };
eval { $v .= pmver('Dist::Zilla::Role::FileMunger','2.101170') };
eval { $v .= pmver('Dist::Zilla::Role::MetaProvider','2.101170') };
eval { $v .= pmver('File::Find','0') };
eval { $v .= pmver('File::Temp','0') };
eval { $v .= pmver('Module::Build','0.3601') };
eval { $v .= pmver('Moose','1.01') };
eval { $v .= pmver('Moose::Util::TypeConstraints','1.01') };
eval { $v .= pmver('PPI','1.206') };
eval { $v .= pmver('Test::More','0') };



# All done.
$v .= <<'EOT';

Thanks for using my code.  I hope it works for you.
If not, please try and include this output in the bug report.

EOT

diag($v);
ok(1, "we really didn't test anything, just reporting data");
exit 0;
