
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "File::Find" => 0,
    "File::Temp" => 0,
    "Module::Build" => "0.3601",
    "Test::More" => "0.88"
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Add the \$AUTHORITY variable and metadata to your distribution",
  "dist_author" => [
    "Apocalypse <APOCAL\@cpan.org>"
  ],
  "dist_name" => "Dist-Zilla-Plugin-Authority",
  "dist_version" => "1.006",
  "license" => "perl",
  "module_name" => "Dist::Zilla::Plugin::Authority",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "Dist::Zilla::Role::FileFinderUser" => "4.102345",
    "Dist::Zilla::Role::FileMunger" => "4.102345",
    "Dist::Zilla::Role::MetaProvider" => "4.102345",
    "Dist::Zilla::Role::PPI" => "4.300001",
    "Dist::Zilla::Util" => 0,
    "File::HomeDir" => 0,
    "File::Spec" => 0,
    "Moose" => "1.03",
    "Moose::Util::TypeConstraints" => "1.01",
    "PPI" => "1.206",
    "perl" => "5.006",
    "strict" => 0,
    "warnings" => 0
  },
  "script_files" => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
