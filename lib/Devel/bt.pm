use strict;
use warnings;

package Devel::bt;

use XSLoader;
use Carp 'croak';
use File::Which 'which';

our $VERSION = '0.01';
XSLoader::load(__PACKAGE__, $VERSION);

sub DB::DB { }

sub find_gdb { which 'gdb' }

sub import {
    my ($class, %args) = @_;

    my $gdb = exists $args{gdb} ? $args{gdb} : $class->find_gdb();
    croak 'Unable to locate gdb binary'
        unless defined $gdb && -x $gdb;

    register_segv_handler($gdb, $^X);
    return;
}

1;
