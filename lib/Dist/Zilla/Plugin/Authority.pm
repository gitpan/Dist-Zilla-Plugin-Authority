#
# This file is part of Dist-Zilla-Plugin-Authority
#
# This software is copyright (c) 2012 by Apocalypse.
#
# This is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
#
use strict; use warnings;
package Dist::Zilla::Plugin::Authority;
{
  $Dist::Zilla::Plugin::Authority::VERSION = '1.006';
}
BEGIN {
  $Dist::Zilla::Plugin::Authority::AUTHORITY = 'cpan:APOCAL';
}

# ABSTRACT: Add the $AUTHORITY variable and metadata to your distribution

use Moose 1.03;
use PPI 1.206;
use File::Spec;
use File::HomeDir;
use Dist::Zilla::Util;

with(
	'Dist::Zilla::Role::MetaProvider' => { -version => '4.102345' },
	'Dist::Zilla::Role::FileMunger' => { -version => '4.102345' },
	'Dist::Zilla::Role::FileFinderUser' => {
		-version => '4.102345',
		default_finders => [ ':InstallModules', ':ExecFiles' ],
	},
    'Dist::Zilla::Role::PPI' => { -version => '4.300001' },
);


{
	use Moose::Util::TypeConstraints 1.01;

	has authority => (
		is => 'ro',
		isa => subtype( 'Str'
			=> where { $_ =~ /^\w+\:\S+$/ }
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
					close $fh or $self->log_fatal( "Unable to close $file - $!" );
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


has locate_comment => (
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

    my $document = $self->ppi_document_for_file($file);

    if ( $self->document_assigns_to_variable( $document, '$AUTHORITY' ) ) {
        $self->log( [ 'skipping %s: assigns to $AUTHORITY', $file->name ] );
        return;
    }

	# Should we use the comment to insert the $AUTHORITY or the pkg declaration?
	if ( $self->locate_comment ) {
		my $comments = $document->find( 'PPI::Token::Comment' );
		my $found_authority;
		if ( ref $comments and ref( $comments ) eq 'ARRAY' ) {
			foreach my $line ( @$comments ) {
				if ( $line =~ /^(\s*)(\#\s+AUTHORITY\b)$/xms ) {
					my ( $ws, $comment ) = ( $1, $2 );
					my $perl = $ws . 'our $AUTHORITY = \'' . $self->authority . "'; $comment\n";

					$self->log_debug( [ 'adding $AUTHORITY assignment to line %d in %s', $line->line_number, $file->name ] );
					$line->set_content( $perl );
					$found_authority = 1;
				}
			}
		}

		if ( ! $found_authority ) {
			$self->log( [ 'skipping %s: consider adding a "# AUTHORITY" comment', $file->name ] );
			return;
		}
	} else {
		return unless my $package_stmts = $document->find( 'PPI::Statement::Package' );

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
				$self->log( [ 'skipping private package %s', $package ] );
				next;
			}

			# Same \x20 hack as seen in PkgVersion, blarh!
			my $perl = "BEGIN {\n  \$${package}::AUTHORITY\x20=\x20'" . $self->authority . "';\n}\n";
			my $doc = PPI::Document->new( \$perl );
			my @children = $doc->schildren;

			$self->log_debug( [ 'adding $AUTHORITY assignment to %s in %s', $package, $file->name ] );

			Carp::carp( "error inserting AUTHORITY in " . $file->name )
				unless $stmt->insert_after( $children[0]->clone )
				and    $stmt->insert_after( PPI::Token::Whitespace->new("\n") );
		}
	}

    $self->save_ppi_document_to_file( $document, $file );
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;


__END__
=pod

=for :stopwords Apocalypse cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee
diff irc mailto metadata placeholders metacpan RJBS FLORA dist ini json
username yml

=encoding utf-8

=for Pod::Coverage metadata munge_files

=head1 NAME

Dist::Zilla::Plugin::Authority - Add the $AUTHORITY variable and metadata to your distribution

=head1 VERSION

  This document describes v1.006 of Dist::Zilla::Plugin::Authority - released January 02, 2012 as part of Dist-Zilla-Plugin-Authority.

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

=head2 locate_comment

A boolean value to control if the $AUTHORITY variable should be added where a
C<# AUTHORITY> comment is found.  If this is set then an appropriate comment
is found, and C<our $AUTHORITY = 'cpan:PAUSEID';> is inserted preceding the
comment on the same line.

This basically implements what L<OurPkgVersion|Dist::Zilla::Plugin::OurPkgVersion>
does for L<PkgVersion|Dist::Zilla::Plugin::PkgVersion>.

Defaults to false.

=head1 SEE ALSO

Please see those modules/websites for more information related to this module.

=over 4

=item *

L<Dist::Zilla|Dist::Zilla>

=item *

L<http://www.perlmonks.org/?node_id=694377|http://www.perlmonks.org/?node_id=694377>

=item *

L<http://perlcabal.org/syn/S11.html#Versioning|http://perlcabal.org/syn/S11.html#Versioning>

=back

=head1 SUPPORT

=head2 Perldoc

You can find documentation for this module with the perldoc command.

  perldoc Dist::Zilla::Plugin::Authority

=head2 Websites

The following websites have more information about this module, and may be of help to you. As always,
in addition to those websites please use your favorite search engine to discover more resources.

=over 4

=item *

MetaCPAN

A modern, open-source CPAN search engine, useful to view POD in HTML format.

L<http://metacpan.org/release/Dist-Zilla-Plugin-Authority>

=item *

Search CPAN

The default CPAN search engine, useful to view POD in HTML format.

L<http://search.cpan.org/dist/Dist-Zilla-Plugin-Authority>

=item *

RT: CPAN's Bug Tracker

The RT ( Request Tracker ) website is the default bug/issue tracking system for CPAN.

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Dist-Zilla-Plugin-Authority>

=item *

AnnoCPAN

The AnnoCPAN is a website that allows community annotations of Perl module documentation.

L<http://annocpan.org/dist/Dist-Zilla-Plugin-Authority>

=item *

CPAN Ratings

The CPAN Ratings is a website that allows community ratings and reviews of Perl modules.

L<http://cpanratings.perl.org/d/Dist-Zilla-Plugin-Authority>

=item *

CPAN Forum

The CPAN Forum is a web forum for discussing Perl modules.

L<http://cpanforum.com/dist/Dist-Zilla-Plugin-Authority>

=item *

CPANTS

The CPANTS is a website that analyzes the Kwalitee ( code metrics ) of a distribution.

L<http://cpants.perl.org/dist/overview/Dist-Zilla-Plugin-Authority>

=item *

CPAN Testers

The CPAN Testers is a network of smokers who run automated tests on uploaded CPAN distributions.

L<http://www.cpantesters.org/distro/D/Dist-Zilla-Plugin-Authority>

=item *

CPAN Testers Matrix

The CPAN Testers Matrix is a website that provides a visual overview of the test results for a distribution on various Perls/platforms.

L<http://matrix.cpantesters.org/?dist=Dist-Zilla-Plugin-Authority>

=item *

CPAN Testers Dependencies

The CPAN Testers Dependencies is a website that shows a chart of the test results of all dependencies for a distribution.

L<http://deps.cpantesters.org/?module=Dist::Zilla::Plugin::Authority>

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

This software is copyright (c) 2012 by Apocalypse.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

The full text of the license can be found in the
'LICENSE' file included with this distribution.

=head1 DISCLAIMER OF WARRANTY

THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

=cut

