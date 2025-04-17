#!/usr/bin/env perl

BEGIN { *CORE::GLOBAL::gmtime = sub(;$) { CORE::gmtime(1440938160) } }

use Test2::V0;
use HTTP::Request;
use WebService::S3::Tiny;

my $mock = mock 'HTTP::Tiny' => override => [
    request => sub { $_[3]{headers}{authorization} },
];

sub slurp($) { local ( @ARGV, $/ ) = @_; scalar <> }

my $s3 = WebService::S3::Tiny->new(
    access_key => 'AKIDEXAMPLE',
    host       => 'example.amazonaws.com',
    region     => 'us-east-1',
    secret_key => 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
    service    => 'service',
);

chdir 't/aws';

for (<{get,post}-*>) {
    utf8::decode my $raw = slurp "$_/$_.req";

    my ($path) = $raw =~ m{^(?:GET|POST) (.+) HTTP/1.1};

    ( $path, my $query ) = split /\?/, $path;

    my @query = split /&/, ( $query // '' );
    @query = map { split /=/, $_, 2 } sort @query;

    my $req = HTTP::Request->parse($raw);

    my %headers = %{ $req->headers };
    delete $headers{'::std_case'};

    is +$s3->request(
        $req->method,
        $path,
        undef,
        $req->content,
        \%headers,
        \@query,
    ) => slurp "$_/$_.authz", $_;
}

done_testing;
