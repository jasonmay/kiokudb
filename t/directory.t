#!/usr/bin/perl

use strict;
use warnings;

use Test::More 'no_plan';
use Test::TempDir;
use Test::Memory::Cycle;

use Scalar::Util qw(blessed);

use ok 'MooseX::Storage::Directory';
use ok 'MooseX::Storage::Directory::Backend::JSPON';

my $dir = MooseX::Storage::Directory->new(
	backend => MooseX::Storage::Directory::Backend::JSPON->new(
		dir => temp_root,
	),
);

{
    package Foo;
    use Moose;

    has foo => (
        isa => "Str",
        is  => "rw",
    );

    has bar => (
        is => "rw",
    );

    has parent => (
        isa => "Foo",
        is  => "rw",
        weak_ref => 1,
    );
}

# Pixie ain't got nuthin on us
my $id;

{
    my $x = Foo->new(
        foo => "dancing",
        bar => Foo->new(
            foo => "oh",
        ),
    );

    memory_cycle_ok($x, "no cycles in proto obj" );

    $x->bar->parent($x);

    memory_cycle_ok($x, "cycle is weak");

    $id = $dir->store($x);

    memory_cycle_ok($x, "store did not introduce cycles");

    is_deeply(
        [ sort $dir->live_objects->live_objects ],
        [ sort $x, $x->bar ],
        "live object set"
    );
};

is_deeply(
    [ $dir->live_objects->live_objects ],
    [ ],
    "live object set empty"
);

{
    my $obj = $dir->lookup($id);

    is( $obj->foo, "dancing", "simple attr" );
    isa_ok( $obj->bar, "Foo", "object attr" );
    is( $obj->bar->foo, "oh", "simple attr of sub object" );
    isa_ok( $obj->bar->parent, "Foo", "object attr of sub object" );
    is( $obj->bar->parent, $obj, "circular ref" );
}

{
    my $x = Foo->new(
        foo => "oink oink",
        bar => my $y = Foo->new(
            foo => "yay",
        ),
    );

    my @ids = $dir->store($x, $y);

    is( scalar(@ids), 2, "got two ids" );

    undef $x;

    is( $dir->live_objects->id_to_object($ids[0]), undef, "first object is dead" );
    is( $dir->live_objects->id_to_object($ids[1]), $y, "second is still alive" );

    my @objects = map { $dir->lookup($_) } @ids;
    
    isa_ok( $objects[0], "Foo" );
    is( $objects[0]->foo, "oink oink", "object retrieved" );
    is( $objects[1], $y, "object is already live" );
    is( $objects[0]->bar, $y, "link recreated" );
}

{
    is_deeply(
        [ $dir->live_objects->live_objects ],
        [],
        "live object set is empty",
    );

    $dir->linker->lazy(1);

    my $obj = $dir->lookup($id);

    is( scalar($dir->live_objects->live_objects), 1, "only one thunk loaded so far" );

    is( blessed($obj), "Data::Thunk::Object", "it's actually a thunk" );

    isa_ok( $obj, "Foo" ); 
    is( $obj->foo, "dancing", "field works" );

    is( blessed($obj), "Foo", "thunk upgraded to object" );

    is( scalar($dir->live_objects->live_objects), 2, "two objects loaded" );

    is( $obj->bar->parent, $obj, "circular ref still correct even when lazy" );
}

is_deeply(
    [ $dir->live_objects->live_objects ],
    [],
    "live object set is empty",
);