package CPAN::Dark;
# ABSTRACT: manages a DarkPAN installation

use strict;
use warnings;

use Carp;
use YAML               0.73;
use File::Path         2.08;
use Path::Class        0.24;
use List::Util         1.20, 'first';
use Archive::Tar       1.76;
use Compress::Zlib     2.035;
use CPAN::Mini::Inject 0.30; # removes old entries of injected modules

sub new
{
    bless { cpmi => CPAN::Mini::Inject->new->parsecfg }, shift;
}

sub create_darkpan
{
    my $self = shift;
    my $cpmi = $self->{cpmi};

    return unless my $repo = $self->should_create_repository;

    File::Path::mkpath( [ dir( $repo, 'authors' ), dir( $repo, 'modules' ) ] );

    $self->write_gz( file( $repo, 'authors', '01mailrc.txt.gz' ), '' );
    $self->write_gz( file( $repo, 'modules', '02packages.details.txt.gz' ),
        <<END_PACKAGE_HEADER );
File:         02packages.details.txt
URL:          http://cpan.perl.org/modules/02packages.details.txt.gz
Description:  Package names found in directory \$CPAN/authors/id/
Columns:      package name, version, path
Intended-For: Automated fetch routines, namespace documentation.
Written-By:   CPAN::Dark $CPAN::Dark::VERSION
Line-Count:   0
Last-Updated: ${ \localtime() }
END_PACKAGE_HEADER

}

sub should_create_repository
{
    my $self = shift;
    my $cpmi = $self->{cpmi};
    my $repo = $cpmi->config->get( 'local' );

    Carp::croak( "No DarkPAN configured!" ) unless $repo;

    return $repo unless -d $repo;
    return $repo unless -f file( $repo, 'authors', '01mailrc.txt.gz' );
    return $repo unless -f
        file( $repo, 'modules', '02packages.details.txt.gz' );

    return;
}

sub write_gz
{
    my ($self, $file, $contents) = @_;

    Carp::croak( "Cannot write to '$file': $!" )
        unless my $fh = $file->open( '>' );

    my $gz = Compress::Zlib::gzopen( $fh, 'wb' );
    $gz->gzwrite( $contents );
    $gz->gzclose;
}

sub inject_files
{
    my $self = shift;
    $self->create_darkpan;

    my $cpmi = $self->{cpmi};

    for my $file (@_)
    {
        Carp::croak( "Cannot find '$file'" ) unless $file and -e $file;

        my $meta    = $self->load_metayaml( $file );
        (my $module = $meta->{name}) =~ s/-/::/g;

        $cpmi->add(
            file     => $file,
            module   => $module,
            version  => $meta->{version},
            authorid => $cpmi->config->{author},
        );
    }

    $cpmi->writelist->inject;
}

sub load_metayaml
{
    my ($self, $file) = @_;

    my $tar = Archive::Tar->new;
    $tar->read( $file );

    return unless my $meta_file = first { /META\.yml$/ } $tar->list_files;
    return YAML::Load( $tar->get_content( $meta_file ) );
}

1;

__END__

=pod

=head1 NAME

CPAN::Dark - manage a DarkPAN installation

=head1 SYNOPSIS

    use CPAN::Dark;
    CPAN::Dark->new->inject_files( @list_of_dist_tarballs );

=head1 DESCRIPTION

A DarkPAN is like the public CPAN except that it's not public. Otherwise it
resembles the public CPAN sufficiently that CPAN installation tools such as
CPAN.pm, CPANPLUS, and cpanminus can install distributions from it.

While existing CPAN tools such as L<CPAN::Mini> allow you to I<mirror> the
public CPAN and L<CPAN::Mini::Inject> allows you to install your own private
distributions into such a mirror, C<CPAN::Dark> takes the opposite approach. A
DarkPAN I<only> contains the distributions you have explicitly installed into
it.

C<CPAN::Dark> relies on the existence of an appropriate
L<CPAN::Mini::Inject::Config>-style configuration file:

=over 4

=item * pointed to by the C<MCPANI_CONFIG> environment variable

=item * present at F<$HOME/.mcpani/config>

=item * present at F</usr/local/etc/mcpani>

=item * present at F</etc/mcpani>

=back

The contents of this file must conform to the described file format, with one
additional parameter. Provide the C<author> configuration to set a default
author for all injected DarkPAN distributions.

=head1 METHODS

This module provides three public methods:

=head2 C<new()>

This constructor creates and returns a new C<CPAN::Dark> object. There is no
user-servicable configuration. This will throw an exception if the
configuration file is missing or invalid.

=head2 C<inject_files( @tarballs )>

Given a list of paths to CPAN-compatible tarballs, this method will inject them
into the configured DarkPAN installation. If the DarkPAN has not yet been
created and initialized, this method will attempt to create it. This method
will also throw an exception if any of the given files do not exist or are not
readable.

=head2 C<create_darkpan()>

This method will create the DarkPAN represented by the current configuration,
if necessary. It will throw an exception if this is not possible. Check your
file permissions if this happens.

=head1 SEE ALSO

L<CPAN::Mini>

L<CPAN::Mini::Inject>

=head1 AUTHOR

chromatic C<< chromatic at wgz dot org >>

=head1 COPYRIGHT & LICENSE

Copyright (c) 2011, chromatic. Redistribution and modification permitted under
the terms of the Artistic License 2.0.
