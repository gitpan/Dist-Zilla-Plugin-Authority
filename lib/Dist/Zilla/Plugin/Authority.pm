#
# This file is part of Dist-Zilla-Plugin-Authority
#
# This software is copyright (c) 2011 by Apocalypse.
#
# This is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
#
use strict; use warnings FATAL => 'all';
package Dist::Zilla::Plugin::Authority;
BEGIN {
  $Dist::Zilla::Plugin::Authority::VERSION = '1.003';
}
BEGIN {
  $Dist::Zilla::Plugin::Authority::AUTHORITY = 'cpan:APOCAL';
}

# ABSTRACT: Add the $AUTHORITY variable and metadata to your distribution

use Moose 1.03;
use PPI 1.206;
use File::Spec;
use File::HomeDir;

with(
	'Dist::Zilla::Role::MetaProvider' => { -version => '4.102345' },
	'Dist::Zilla::Role::FileMunger' => { -version => '4.102345' },
	'Dist::Zilla::Role::FileFinderUser' => {
		-version => '4.102345',
		default_finders => [ ':InstallModules', ':ExecFiles' ],
	},
);


{
	use Moose::Util::TypeConstraints 1.01;

	has authority => (
		is => 'ro',
		isa => subtype( 'Str'
			=> where { $_ =~ /^\w+\:\w+$/ }
			=> message { "Authority must be in the form of 'cpan:PAUSEID'" }
		),
		lazy => 1,
		default => sub {
			my $self = shift;
			my $stash = $self->zilla->stash_named( '%PAUSE' );
			if ( defined $stash ) {
				$self->log_debug( [ 'using PAUSE id "%s" for AUTHORITY from Dist::Zilla config', uc( $stash->username ) ] );
				return 'cpan:' . uc( $stash->username );
			} else {
				# Argh, try the .pause file?
				# Code ripped off from Dist::Zilla::Plugin::UploadToCPAN v4.200001 - thanks RJBS!
				my $file = File::Spec->catfile( File::HomeDir->my_home, '.pause' );
				if ( -f $file ) {
					open my $fh, '<', $file or $self->log_fatal( "Unable to open $file - $!" );
					while (<$fh>) {
						next if /^\s*(?:#.*)?$/;
						my ( $k, $v ) = /^\s*(\w+)\s+(.+)$/;
						if ( $k =~ /^user$/i ) {
							$self->log_debug( [ 'using PAUSE id "%s" for AUTHORITY from ~/.pause', uc( $v ) ] );
							return 'cpan:' . uc( $v );
						}
					}
					$self->log_fatal( 'PAUSE user not found in ~/.pause' );
				} else {
					$self->log_fatal( 'PAUSE credentials not found in "config.ini" or "dist.ini" or "~/.pause"! Please set it or specify an authority for this plugin.' );
				}
			}
		},
	);

	no Moose::Util::TypeConstraints;
}


has do_metadata => (
	is => 'ro',
	isa => 'Bool',
	default => 1,
);


has do_munging => (
	is => 'ro',
	isa => 'Bool',
	default => 1,
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

	return if ! $self->do_munging;

	$self->_munge_file( $_ ) for @{ $self->found_files };
}

sub _munge_file {
	my( $self, $file ) = @_;

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
		if ( $stmt->content =~ /package\s*(?:#.*)?\n\s*\Q$package/ ) {
			$self->log([ 'skipping private package %s', $package ]);
			next;
		}

		# Same \x20 hack as seen in PkgVersion, blarh!
		my $perl = "BEGIN {\n  \$$package\::AUTHORITY\x20=\x20'" . $self->authority . "';\n}\n";
		my $doc = PPI::Document->new( \$perl );
		my @children = $doc->schildren;

		$self->log_debug( [ 'adding $AUTHORITY assignment to %s in %s', $package, $file->name ] );

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

=for stopwords RJBS metadata FLORA dist ini json username yml

=head1 NAME

Dist::Zilla::Plugin::Authority - Add the $AUTHORITY variable and metadata to your distribution

=head1 VERSION

  This document describes v1.003 of Dist::Zilla::Plugin::Authority - released February 04, 2011 as part of Dist-Zilla-Plugin-Authority.

=head1 DESCRIPTION

This plugin adds the authority data to your distribution. It adds the data to your modules and metadata. Normally it
looks for the PAUSE author id in your L<Dist::Zilla> configuration. If you want to override it, please use the 'authority'
attribute.

	# In your dist.ini:
	[Authority]

This code will be added to any package declarations in your perl files:

	BEGIN {
	  $Dist::Zilla::Plugin::Authority::AUTHORITY = 'cpan:APOCAL';
	}

Your metadata ( META.yml or META.json ) will have an entry looking like this:

	x_authority => 'cpan:APOCAL'

=head1 ATTRIBUTES

=head2 authority

The authority you want to use. It should be something like C<cpan:APOCAL>.

Defaults to the username set in the %PAUSE stash in the global config.ini or dist.ini ( Dist::Zilla v4 addition! )

If you prefer to not put it in config/dist.ini you can put it in "~/.pause" just like Dist::Zilla did before v4.

=head2 do_metadata

A boolean value to control if the authority should be added to the metadata.

Defaults to true.

=head2 do_munging

A boolean value to control if the $AUTHORITY variable should be added to the modules.

Defaults to true.

=head1 SEE ALSO

Please see those modules/websites for more information related to this module.

=over 4

=item *

L<Dist::Zilla>

=item *

L<http://www.perlmonks.org/?node_id=694377>

=item *

L<http://perlcabal.org/syn/S11.html#Versioning>

=back

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders

=head1 SUPPORT

=head2 Perldoc

You can find documentation for this module with the perldoc command.

  perldoc Dist::Zilla::Plugin::Authority

=head2 Websites

The following websites have more information about this module, and may be of help to you. As always,
in addition to those websites please use your favorite search engine to discover more resources.

=over 4

=item *

Search CPAN

L<http://search.cpan.org/dist/Dist-Zilla-Plugin-Authority>

=item *

RT: CPAN's Bug Tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Dist-Zilla-Plugin-Authority>

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

CPANTS Kwalitee

L<http://cpants.perl.org/dist/overview/Dist-Zilla-Plugin-Authority>

=item *

CPAN Testers Results

L<http://cpantesters.org/distro/D/Dist-Zilla-Plugin-Authority.html>

=item *

CPAN Testers Matrix

L<http://matrix.cpantesters.org/?dist=Dist-Zilla-Plugin-Authority>

=back

=head2 Email

You can email the author of this module at C<APOCAL at cpan.org> asking for help with any problems you have.

=head2 Internet Relay Chat

You can get live help by using IRC ( Internet Relay Chat ). If you don't know what IRC is,
please read this excellent guide: L<http://en.wikipedia.org/wiki/Internet_Relay_Chat>. Please
be courteous and patient when talking to us, as we might be busy or sleeping! You can join
those networks/channels and get help:

=over 4

=item *

irc.perl.org

You can connect to the server at 'irc.perl.org' and join this channel: #perl-help then talk to this person for help: Apocalypse.

=item *

irc.freenode.net

You can connect to the server at 'irc.freenode.net' and join this channel: #perl then talk to this person for help: Apocal.

=item *

irc.efnet.org

You can connect to the server at 'irc.efnet.org' and join this channel: #perl then talk to this person for help: Ap0cal.

=back

=head2 Bugs / Feature Requests

Please report any bugs or feature requests by email to C<bug-dist-zilla-plugin-authority at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Dist-Zilla-Plugin-Authority>. You will be automatically notified of any
progress on the request by the system.

=head2 Source Code

The code is open to the world, and available for you to hack on. Please feel free to browse it and play
with it, or whatever. If you want to contribute patches, please send me a diff or prod me to pull
from your repository :)

L<http://github.com/apocalypse/perl-dist-zilla-plugin-authority>

  git clone git://github.com/apocalypse/perl-dist-zilla-plugin-authority.git

=head1 AUTHOR

Apocalypse <APOCAL@cpan.org>

=head1 ACKNOWLEDGEMENTS

This module is basically a rip-off of RJBS' excellent L<Dist::Zilla::Plugin::PkgVersion>, thanks!

Props goes out to FLORA for prodding me to improve this module!

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Apocalypse.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

The full text of the license can be found in the LICENSE file included with this distribution.

=cut

