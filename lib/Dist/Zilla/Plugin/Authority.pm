# 
# This file is part of Dist-Zilla-Plugin-Authority
# 
# This software is copyright (c) 2010 by Apocalypse.
# 
# This is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
# 
use strict; use warnings;
package Dist::Zilla::Plugin::Authority;
BEGIN {
  $Dist::Zilla::Plugin::Authority::VERSION = '1.000';
}
BEGIN {
  $Dist::Zilla::Plugin::Authority::AUTHORITY = 'cpan:APOCAL';
}

# ABSTRACT: Add an $AUTHORITY to your packages

use Moose 1.01;
use PPI 1.206;

# TODO wait for improved Moose that allows "with 'Foo::Bar' => { -version => 1.23 };"
use Dist::Zilla::Role::MetaProvider 2.101170;
use Dist::Zilla::Role::FileMunger 2.101170;
use Dist::Zilla::Role::FileFinderUser 2.101170;
with(
	'Dist::Zilla::Role::MetaProvider',
	'Dist::Zilla::Role::FileMunger',
	'Dist::Zilla::Role::FileFinderUser' => {
		default_finders => [ ':InstallModules' ],
	},
);


{
	use Moose::Util::TypeConstraints 1.01;

	has authority => (
		is => 'ro',
		isa => subtype( 'Str'
			=> where { $_ =~ /^\w+\:\w+$/ }
			=> message { "Authority must be in the form of 'cpan:PAUSEID'." }
		),
		required => 1,
	);

	no Moose::Util::TypeConstraints;
}


has do_metadata => (
	is => 'ro',
	isa => 'Bool',
	default => 0,
);

sub metadata {
	my( $self ) = @_;

	return if ! $self->do_metadata;

	$self->log_debug( 'adding AUTHORITY to metadata' );

	return {
		'x_authority'	=> $self->authority,
	};
}

sub munge_files {
	my( $self ) = @_;

	$self->_munge_file( $_ ) for @{ $self->found_files };
}

sub _munge_file {
	my( $self, $file ) = @_;

	return                           if $file->name    =~ /\.t$/i;
	return $self->_munge_perl($file) if $file->name    =~ /\.(?:pm|pl)$/i;
	return $self->_munge_perl($file) if $file->content =~ /^#!(?:.*)perl(?:$|\s)/;
	return;
}

sub _munge_perl {
	my( $self, $file ) = @_;

	my $content = $file->content;
	my $document = PPI::Document->new( \$content ) or Carp::croak( PPI::Document->errstr );

	{
		my $code_only = $document->clone;
		$code_only->prune( "PPI::Token::$_" ) for qw( Comment Pod Quote Regexp );
		if ( $code_only->serialize =~ /\$AUTHORITY\s*=/sm ) {
			$self->log( [ 'skipping %s: assigns to $AUTHORITY', $file->name ] );
			return;
		}
	}

	return unless my $package_stmts = $document->find('PPI::Statement::Package');

	my %seen_pkgs;

	for my $stmt ( @$package_stmts ) {
		my $package = $stmt->namespace;

		# Thanks to rafl ( Florian Ragwitz ) for this
		if ( $seen_pkgs{ $package }++ ) {
			$self->log( [ 'skipping package re-declaration for %s', $package ] );
			next;
		}

		# Thanks to autarch ( Dave Rolsky ) for this
		if ( $stmt->content =~ /package\s*\n\s*\Q$package/ ) {
			$self->log([ 'skipping package for %s, it looks like a monkey patch', $package ]);
			next;
		}

		# Same \x20 hack as seen in PkgVersion, blarh!
		my $perl = "BEGIN {\n  \$$package\::AUTHORITY\x20=\x20'" . $self->authority . "';\n}\n";
		my $doc = PPI::Document->new( \$perl );
		my @children = $doc->schildren;

		$self->log_debug( [ 'adding $AUTHORITY assignment in %s', $file->name ] );

		Carp::carp( "error inserting AUTHORITY in " . $file->name )
			unless $stmt->insert_after( $children[0]->clone )
			and    $stmt->insert_after( PPI::Token::Whitespace->new("\n") );
	}

	$file->content( $document->serialize );
}


no Moose;
__PACKAGE__->meta->make_immutable;
1;


__END__
=pod

=for Pod::Coverage metadata munge_files

=for stopwords RJBS json metadata yml

=head1 NAME

Dist::Zilla::Plugin::Authority - Add an $AUTHORITY to your packages

=head1 VERSION

  This document describes v1.000 of Dist::Zilla::Plugin::Authority - released May 30, 2010 as part of Dist-Zilla-Plugin-Authority.

=head1 DESCRIPTION

This plugin adds the $AUTHORITY marker to your packages. Also, it can add the authority information
to the metadata, if requested.

	# In your dist.ini:
	[Authority]
	authority = cpan:APOCAL
	do_metadata = 1

The resulting hunk of code would look something like this:

	BEGIN {
	  $Dist::Zilla::Plugin::Authority::AUTHORITY = 'cpan:APOCAL';
	}

This code will be added to any package declarations in your perl files.

=head1 ATTRIBUTES

=head2 authority

The authority you want to use. It should be something like C<cpan:APOCAL>.

Required.

=head2 do_metadata

A boolean value to control if the authority should be added to the metadata. ( META.yml or META.json )

Defaults to false.

The metadata will look like this:

	x_authority => 'cpan:APOCAL'

=head1 SEE ALSO

=over 4

=item *

L<Dist::Zilla>

=item *

L<http://www.perlmonks.org/?node_id=694377>

=item *

L<http://perlcabal.org/syn/S11.html#Versioning>

=back

=for :stopwords CPAN AnnoCPAN RT CPANTS Kwalitee diff

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

  perldoc Dist::Zilla::Plugin::Authority

=head2 Websites

=over 4

=item *

Search CPAN

L<http://search.cpan.org/dist/Dist-Zilla-Plugin-Authority>

=item *

AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Dist-Zilla-Plugin-Authority>

=item *

CPAN Ratings

L<http://cpanratings.perl.org/d/Dist-Zilla-Plugin-Authority>

=item *

CPAN Forum

L<http://cpanforum.com/dist/Dist-Zilla-Plugin-Authority>

=item *

RT: CPAN's Bug Tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Dist-Zilla-Plugin-Authority>

=item *

CPANTS Kwalitee

L<http://cpants.perl.org/dist/overview/Dist-Zilla-Plugin-Authority>

=item *

CPAN Testers Results

L<http://cpantesters.org/distro/D/Dist-Zilla-Plugin-Authority.html>

=item *

CPAN Testers Matrix

L<http://matrix.cpantesters.org/?dist=Dist-Zilla-Plugin-Authority>

=item *

Source Code Repository

The code is open to the world, and available for you to hack on. Please feel free to browse it and play
with it, or whatever. If you want to contribute patches, please send me a diff or prod me to pull
from your repository :)

L<http://github.com/apocalypse/perl-dist-zilla-plugin-authority>

=back

=head2 Bugs

Please report any bugs or feature requests to C<bug-dist-zilla-plugin-authority at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Dist-Zilla-Plugin-Authority>.  I will be
notified, and then you'll automatically be notified of progress on your bug as I make changes.

=head1 AUTHOR

  Apocalypse <APOCAL@cpan.org>

=head1 ACKNOWLEDGEMENTS

This module is basically a rip-off of RJBS' excellent L<Dist::Zilla::Plugin::PkgVersion>, thanks!

Props goes out to FLORA for prodding me to improve this module!

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by Apocalypse.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

