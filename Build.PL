
use strict;
use warnings;

use Module::Build 0.3601;

my %module_build_args = (
  'build_requires' => {
    'File::Find' => '0',
    'File::Temp' => '0',
    'Module::Build' => '0.3601',
    'Test::More' => '0'
  },
  'configure_requires' => {
    'Module::Build' => '0.3601'
  },
  'dist_abstract' => 'Add an $AUTHORITY to your packages',
  'dist_author' => [
    'Apocalypse <APOCAL@cpan.org>'
  ],
  'dist_name' => 'Dist-Zilla-Plugin-Authority',
  'dist_version' => '1.000',
  'license' => 'perl',
  'module_name' => 'Dist::Zilla::Plugin::Authority',
  'recommends' => {},
  'requires' => {
    'Dist::Zilla::Role::FileFinderUser' => '2.101170',
    'Dist::Zilla::Role::FileMunger' => '2.101170',
    'Dist::Zilla::Role::MetaProvider' => '2.101170',
    'Moose' => '1.01',
    'Moose::Util::TypeConstraints' => '1.01',
    'PPI' => '1.206',
    'perl' => '5.006'
  },
  'script_files' => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
