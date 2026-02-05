#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../";
use lib "$FindBin::Bin/lib";

use Test::More;
use YAML::XS;
use File::Spec;
use JSON;
use File::Temp qw(tempfile tempdir);

require StubZM;

use ZmEventNotification::Config qw(:all);
use ZmEventNotification::Constants qw(:all);

# Load config
my $fixtures = File::Spec->catdir($FindBin::Bin, 'fixtures');
my $cfg = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_es.yml'));
my $sec = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_secrets.yml'));
$ZmEventNotification::Config::secrets = $sec;
loadEsConfigSettings($cfg);

# Track HTTP requests
our @http_requests;
our $http_response_code = 200;
our $http_response_body = '{}';

# Mock LWP and HTTP modules
BEGIN {
    $INC{'LWP/UserAgent.pm'} = __FILE__;
    $INC{'HTTP/Request.pm'} = __FILE__;

    package HTTP::Request;
    sub new {
        my ($class, $method, $uri) = @_;
        return bless { method => $method, uri => $uri, headers => {}, content => '' }, $class;
    }
    sub header {
        my ($self, $key, $value) = @_;
        $self->{headers}{$key} = $value;
    }
    sub content {
        my ($self, $content) = @_;
        $self->{content} = $content if defined $content;
        return $self->{content};
    }

    package LWP::UserAgent;
    sub new { bless {}, shift }
    sub request {
        my ($self, $req) = @_;
        push @main::http_requests, {
            method => $req->{method},
            uri => $req->{uri},
            headers => $req->{headers},
            content => $req->{content},
        };
        return MockHTTPResponse->new($main::http_response_code, $main::http_response_body);
    }

    package MockHTTPResponse;
    sub new {
        my ($class, $code, $body) = @_;
        return bless { code => $code, body => $body }, $class;
    }
    sub is_success { shift->{code} == 200 }
    sub decoded_content { shift->{body} }
    sub status_line { "HTTP/1.1 " . shift->{code} }
}

# Mock Crypt::OpenSSL::RSA
our $rsa_sign_result = 'mocksignature';
our $rsa_new_key_called = 0;

BEGIN {
    $INC{'Crypt/OpenSSL/RSA.pm'} = __FILE__;
    package Crypt::OpenSSL::RSA;
    sub new_private_key {
        my ($class, $key) = @_;
        $main::rsa_new_key_called = 1;
        return bless { key => $key }, $class;
    }
    sub use_sha256_hash { 1 }
    sub sign {
        my ($self, $payload) = @_;
        return $main::rsa_sign_result;
    }
}

# Override try_use to allow Crypt::OpenSSL::RSA
no warnings 'redefine';
*main::try_use = sub {
    my $module = shift;
    return 1 if $module eq 'Crypt::OpenSSL::RSA';
    return 0;
};

use_ok('ZmEventNotification::FCM');
ZmEventNotification::FCM->import(':all');

# Reset test state
sub reset_state {
    @http_requests = ();
    $http_response_code = 200;
    $http_response_body = '{}';
    $rsa_new_key_called = 0;
    $fcm_config{cached_access_token} = undef;
    $fcm_config{cached_access_token_expiry} = 0;
    $fcm_config{cached_project_id} = undef;
}

# ===== _base64url_encode tests =====
subtest '_base64url_encode' => sub {
    # Standard base64 characters should be URL-safe
    my $result = ZmEventNotification::FCM::_base64url_encode('test');
    ok($result !~ /\+/, 'No + characters');
    ok($result !~ /\//, 'No / characters');
    ok($result !~ /=/, 'No padding');
    ok($result !~ /\n/, 'No newlines');

    # Known test vector
    my $input = '{"alg":"RS256","typ":"JWT"}';
    my $encoded = ZmEventNotification::FCM::_base64url_encode($input);
    # Should be standard JWT header encoding
    ok(length($encoded) > 0, 'Encodes non-empty string');
};

# ===== _check_monthly_limit tests =====
subtest '_check_monthly_limit resets on month change' => sub {
    my $curmonth = (localtime)[4];
    my $lastmonth = ($curmonth + 11) % 12;  # Previous month

    my $obj = {
        token => 'test_token_1234567890',
        invocations => { count => 100, at => $lastmonth }
    };

    my $result = ZmEventNotification::FCM::_check_monthly_limit($obj);
    is($result, 0, 'Returns 0 after reset');
    is($obj->{invocations}->{count}, 0, 'Count reset to 0');
};

subtest '_check_monthly_limit blocks when exceeded' => sub {
    my $curmonth = (localtime)[4];

    my $obj = {
        token => 'test_token_1234567890',
        invocations => { count => DEFAULT_MAX_FCM_PER_MONTH_PER_TOKEN + 1, at => $curmonth }
    };

    my $result = ZmEventNotification::FCM::_check_monthly_limit($obj);
    is($result, 1, 'Returns 1 when limit exceeded');
};

subtest '_check_monthly_limit allows when under limit' => sub {
    my $curmonth = (localtime)[4];

    my $obj = {
        token => 'test_token_1234567890',
        invocations => { count => 10, at => $curmonth }
    };

    my $result = ZmEventNotification::FCM::_check_monthly_limit($obj);
    is($result, 0, 'Returns 0 when under limit');
};

subtest '_check_monthly_limit handles undefined invocations' => sub {
    my $obj = { token => 'test_token_1234567890' };

    my $result = ZmEventNotification::FCM::_check_monthly_limit($obj);
    is($result, 0, 'Returns 0 when no invocations');
};

# ===== get_google_access_token tests =====
subtest 'get_google_access_token returns cached token' => sub {
    reset_state();
    $fcm_config{cached_access_token} = 'cached_token_xyz';
    $fcm_config{cached_access_token_expiry} = time() + 3600;  # Valid for 1 hour

    my $token = get_google_access_token('/fake/path.json');

    is($token, 'cached_token_xyz', 'Returns cached token');
    is(scalar @http_requests, 0, 'No HTTP request made');
};

subtest 'get_google_access_token creates JWT and exchanges for token' => sub {
    reset_state();
    $http_response_body = encode_json({
        access_token => 'new_access_token_abc',
        expires_in => 3600
    });

    # Create temp service account file
    my ($fh, $filename) = tempfile(SUFFIX => '.json');
    my $service_account = {
        client_email => 'test@project.iam.gserviceaccount.com',
        private_key => "-----BEGIN RSA PRIVATE KEY-----\nMOCK\n-----END RSA PRIVATE KEY-----",
        token_uri => 'https://oauth2.googleapis.com/token',
        project_id => 'test-project-123'
    };
    print $fh encode_json($service_account);
    close($fh);

    my $token = get_google_access_token($filename);

    is($token, 'new_access_token_abc', 'Returns new access token');
    ok($rsa_new_key_called, 'RSA key was loaded');
    is(scalar @http_requests, 1, 'One HTTP request made');
    is($http_requests[0]->{method}, 'POST', 'POST request');
    like($http_requests[0]->{uri}, qr/oauth2\.googleapis\.com/, 'Correct token URI');
    like($http_requests[0]->{content}, qr/grant_type=.*jwt-bearer/, 'Contains JWT grant type');
    is($fcm_config{cached_project_id}, 'test-project-123', 'Project ID cached');

    unlink($filename);
};

subtest 'get_google_access_token handles missing file' => sub {
    reset_state();

    my $token = get_google_access_token('/nonexistent/file.json');

    is($token, undef, 'Returns undef for missing file');
};

subtest 'get_google_access_token handles token request failure' => sub {
    reset_state();
    $http_response_code = 401;
    $http_response_body = '{"error": "unauthorized"}';

    my ($fh, $filename) = tempfile(SUFFIX => '.json');
    my $service_account = {
        client_email => 'test@project.iam.gserviceaccount.com',
        private_key => "-----BEGIN RSA PRIVATE KEY-----\nMOCK\n-----END RSA PRIVATE KEY-----",
        token_uri => 'https://oauth2.googleapis.com/token',
        project_id => 'test-project'
    };
    print $fh encode_json($service_account);
    close($fh);

    my $token = get_google_access_token($filename);

    is($token, undef, 'Returns undef on failure');

    unlink($filename);
};

subtest 'get_google_access_token uses default token_uri' => sub {
    reset_state();
    $http_response_body = encode_json({
        access_token => 'token123',
        expires_in => 3600
    });

    my ($fh, $filename) = tempfile(SUFFIX => '.json');
    my $service_account = {
        client_email => 'test@project.iam.gserviceaccount.com',
        private_key => "-----BEGIN RSA PRIVATE KEY-----\nMOCK\n-----END RSA PRIVATE KEY-----",
        # No token_uri - should use default
        project_id => 'test-project'
    };
    print $fh encode_json($service_account);
    close($fh);

    my $token = get_google_access_token($filename);

    like($http_requests[0]->{uri}, qr/oauth2\.googleapis\.com\/token/, 'Uses default token URI');

    unlink($filename);
};

# ===== Token file operations =====
subtest 'readTokenFile returns undef for missing file' => sub {
    reset_state();
    local $fcm_config{token_file} = '/nonexistent/tokens.json';

    my $result = readTokenFile();
    is($result, undef, 'Returns undef for missing file');
};

subtest 'readTokenFile parses valid JSON' => sub {
    reset_state();
    my $dir = tempdir(CLEANUP => 1);
    my $token_file = "$dir/tokens.json";
    local $fcm_config{token_file} = $token_file;

    my $data = { tokens => { 'abc123' => { platform => 'ios' } } };
    open(my $fh, '>', $token_file);
    print $fh encode_json($data);
    close($fh);

    my $result = readTokenFile();
    ok($result, 'Returns data');
    is($result->{tokens}->{'abc123'}->{platform}, 'ios', 'Correct data parsed');
};

subtest 'readTokenFile returns undef for invalid JSON' => sub {
    reset_state();
    my $dir = tempdir(CLEANUP => 1);
    my $token_file = "$dir/tokens.json";
    local $fcm_config{token_file} = $token_file;

    open(my $fh, '>', $token_file);
    print $fh 'not valid json';
    close($fh);

    my $result = readTokenFile();
    is($result, undef, 'Returns undef for invalid JSON');
};

subtest 'writeTokenFile creates file' => sub {
    reset_state();
    my $dir = tempdir(CLEANUP => 1);
    my $token_file = "$dir/tokens.json";
    local $fcm_config{token_file} = $token_file;

    my $data = { tokens => { 'xyz789' => { platform => 'android' } } };
    writeTokenFile($data);

    ok(-f $token_file, 'File created');
    open(my $fh, '<', $token_file);
    my $content = do { local $/; <$fh> };
    close($fh);

    my $parsed = decode_json($content);
    is($parsed->{tokens}->{'xyz789'}->{platform}, 'android', 'Correct data written');
};

# ===== deleteFCMToken tests =====
subtest 'deleteFCMToken removes token from file and connections' => sub {
    reset_state();
    my $dir = tempdir(CLEANUP => 1);
    my $token_file = "$dir/tokens.json";
    local $fcm_config{token_file} = $token_file;

    # Setup token file
    my $data = {
        tokens => {
            'token_to_delete' => { platform => 'ios' },
            'token_to_keep' => { platform => 'android' }
        }
    };
    writeTokenFile($data);

    # Setup active connections
    @main::active_connections = (
        { token => 'token_to_delete', state => VALID_CONNECTION, type => FCM },
        { token => 'token_to_keep', state => VALID_CONNECTION, type => FCM },
    );

    deleteFCMToken('token_to_delete');

    # Check file
    my $result = readTokenFile();
    ok(!exists $result->{tokens}->{'token_to_delete'}, 'Token removed from file');
    ok(exists $result->{tokens}->{'token_to_keep'}, 'Other token preserved');

    # Check connections
    my @deleted = grep { $_->{token} eq 'token_to_delete' } @main::active_connections;
    is($deleted[0]->{state}, INVALID_CONNECTION, 'Connection marked INVALID');
};

done_testing();
