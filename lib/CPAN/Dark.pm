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
