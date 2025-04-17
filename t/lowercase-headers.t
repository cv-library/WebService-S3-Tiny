#!/usr/bin/env perl

use Test2::V0;
use WebService::S3::Tiny;

my $mock = mock 'HTTP::Tiny' => override => [ request => sub { \@_ } ];

my $s3 = WebService::S3::Tiny->new(
    access_key => 1,
    host       => 1,
    secret_key => 1,
);

like $s3->put_object( foo => 'bar', 'baz', { 'Foo-Bar' => 'Baz' } ) => array {
    item 3 => {
        headers => {
            'foo-bar' => 'Baz',
        },
    };
    etc;
};

done_testing;
