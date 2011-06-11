#! perl

use Test::More;

main();
exit;

sub main
{
    my $module = 'CPAN::Dark';
    use_ok( $module ) or exit;

    done_testing();
}
