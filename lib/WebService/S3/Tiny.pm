package WebService::S3::Tiny 0.001;

use strict;
use warnings;

use Carp;
use Digest::SHA qw/hmac_sha256 hmac_sha256_hex sha256_hex/;
use HTTP::Tiny;

my %url_enc = map { chr, sprintf '%%%02X', $_ } 0..255;

sub new {
    my ( $class, %args ) = @_;

    $args{access_key} // croak '"access_key" is required';
    $args{host}       // croak '"host" is required';
    $args{region}     //= 'us-east-1';
    $args{secret_key} // croak '"secret_key" is requried';
    $args{service}    //= 's3';
    $args{ua}         //= HTTP::Tiny->new;

    bless \%args, $class;
}

sub add_bucket {
    my ( $self, $bucket ) = @_;

    $self->_request( 'PUT', $bucket );
}

sub del_bucket {
    my ( $self, $bucket ) = @_;

    $self->_request( 'DELETE', $bucket );
}

sub get_bucket {
    my ( $self, $bucket, %query ) = @_;

    # Use the recommended API version.
    # https://docs.aws.amazon.com/AmazonS3/latest/API/v2-RESTBucketGET.html
    $query{'list-type'} = 2;

    $self->_request( 'GET', $bucket, undef, undef, \%query );
}

sub add_object {
    my ( $self, $bucket, $object, $content ) = @_;

    $self->_request( 'PUT', $bucket, $object, $content );
}

sub del_object {
    my ( $self, $bucket, $object ) = @_;

    $self->_request( 'DELETE', $bucket, $object );
}

sub get_object {
    my ( $self, $bucket, $object ) = @_;

    $self->_request( 'GET', $bucket, $object );
}

sub _normalize_path {
    my @old_parts = split m(/), $_[0], -1;
    my @new_parts;

    for ( 0 .. $#old_parts ) {
        my $part = $old_parts[$_];

        if ( $part eq '..' ) {
            pop @new_parts;
        }
        elsif ( $part ne '.' && ( length $part || $_ == $#old_parts ) ) {
            push @new_parts, $part;
        }
    }

    '/' . join '/', @new_parts;
}

sub _request {
    my ( $self, $method, $bucket, $object, $content, $query, $headers ) = @_;

    $headers //= {};
    $query   //= {};

    utf8::encode my $path = _normalize_path( join '/', '', $bucket, $object // () );

    $path =~ s|([^A-Za-z0-9\-\._~/])|$url_enc{$1}|g;

    $headers->{host} = $self->{host} =~ s|^https?://||r;

    my ( $s, $m, $h, $d, $M, $y ) = gmtime;

    my $time = $headers->{'x-amz-date'} = sprintf '%d%02d%02dT%02d%02d%02dZ',
        $y + 1900, $M + 1, $d, $h, $m, $s;

    my $date = substr $time, 0, 8;

    # Let the user pass their own checksums if they have them.
    my $sha = $headers->{'x-amz-content-sha256'} // sha256_hex $content // '';

    # Put requests must have the checksum header.
    $headers->{'x-amz-content-sha256'} = $sha if $method eq 'PUT';

    my $creq = "$method\n$path\n" . HTTP::Tiny->www_form_urlencode($query);

    for my $k ( sort keys %$headers ) {
        my $v = $headers->{$k};

        $creq .= "\n$k:";

        $creq .= join ',',
            map s/\s+/ /gr,
            map s/^\s+|\s+$//gr,
            map split(/\n/),
            ref $v ? @$v : $v;
    }

    $creq .= "\n\n";

    $creq .= my $signed_headers = join ';', sort keys %$headers;

    $creq .= "\n$sha";

    my $cred_scope = "$date/$self->{region}/$self->{service}/aws4_request";

    utf8::encode $creq;

    my $sig = hmac_sha256_hex(
        "AWS4-HMAC-SHA256\n$time\n$cred_scope\n" . sha256_hex($creq),
        hmac_sha256(
            aws4_request => hmac_sha256(
                $self->{service} => hmac_sha256(
                    $self->{region},
                    hmac_sha256( $date, "AWS4$self->{secret_key}" ),
                ),
            ),
        ),
    );

    $headers->{authorization} = join(
        ', ',
        "AWS4-HMAC-SHA256 Credential=$self->{access_key}/$cred_scope",
        "SignedHeaders=$signed_headers",
        "Signature=$sig",
    );

    # HTTP::Tiny doesn't like us providing our own host header, but we have to
    # sign it, so let's hope HTTP::Tiny calculates the same value as us :-S
    delete $headers->{host};

    $self->{ua}->request(
        $method,
        "$self->{host}$path?" . HTTP::Tiny->www_form_urlencode($query),
        { content => $content, headers => $headers },
    );
}

1;
