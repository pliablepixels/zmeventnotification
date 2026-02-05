#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../";
use lib "$FindBin::Bin/lib";

use Test::More;
use YAML::XS;
use File::Spec;

require StubZM;

use ZmEventNotification::Config qw(:all);
use ZmEventNotification::Constants qw(:all);

# Load config
my $fixtures = File::Spec->catdir($FindBin::Bin, 'fixtures');
my $cfg = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_es.yml'));
my $sec = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_secrets.yml'));
$ZmEventNotification::Config::secrets = $sec;
loadEsConfigSettings($cfg);

# Track mock calls
our @mqtt_simple_new_calls;
our @mqtt_ssl_new_calls;
our @mqtt_login_calls;
our $mqtt_new_return_value;

# Mock MQTT modules
BEGIN {
    # Mock IO::Socket::SSL for SSL_VERIFY_NONE constant
    $INC{'IO/Socket/SSL.pm'} = __FILE__;
    package IO::Socket::SSL;
    sub SSL_VERIFY_NONE { 0 }

    # Mock Time::HiRes - must be declared before loading MQTT module
    $INC{'Time/HiRes.pm'} = __FILE__;
    package Time::HiRes;
    sub gettimeofday { return (CORE::time(), 0) }
    sub import { 1 }

    package main;
    # Mock Net::MQTT::Simple
    $INC{'Net/MQTT/Simple.pm'} = __FILE__;
    package Net::MQTT::Simple;
    sub new {
        my ($class, $server) = @_;
        push @main::mqtt_simple_new_calls, { class => $class, server => $server };
        return $main::mqtt_new_return_value;
    }
    sub login {
        my ($self, $user, $pass) = @_;
        push @main::mqtt_login_calls, { user => $user, pass => $pass };
    }
    sub import { 1 }

    # Mock Net::MQTT::Simple::SSL
    $INC{'Net/MQTT/Simple/SSL.pm'} = __FILE__;
    package Net::MQTT::Simple::SSL;
    sub new {
        my ($class, $server, $sockopts) = @_;
        push @main::mqtt_ssl_new_calls, { class => $class, server => $server, sockopts => $sockopts };
        return $main::mqtt_new_return_value;
    }
    sub login {
        my ($self, $user, $pass) = @_;
        push @main::mqtt_login_calls, { user => $user, pass => $pass };
    }
    sub import { 1 }
}

use_ok('ZmEventNotification::MQTT');
ZmEventNotification::MQTT->import(':all');

# Reset test state before each test
sub reset_mocks {
    @mqtt_simple_new_calls = ();
    @mqtt_ssl_new_calls = ();
    @mqtt_login_calls = ();
    $mqtt_new_return_value = bless {}, 'MockMQTT';
    @main::active_connections = ();
}

# ===== initMQTT tests =====
subtest 'initMQTT without auth' => sub {
    reset_mocks();
    local $mqtt_config{username} = undef;
    local $mqtt_config{password} = undef;
    local $mqtt_config{server} = 'localhost:1883';

    initMQTT();

    is(scalar @mqtt_simple_new_calls, 1, 'Net::MQTT::Simple->new called once');
    is($mqtt_simple_new_calls[0]->{server}, 'localhost:1883', 'Correct server passed');
    is(scalar @mqtt_login_calls, 0, 'login not called without auth');
    is(scalar @main::active_connections, 1, 'Connection added to active_connections');
    is($main::active_connections[0]->{type}, MQTT, 'Connection type is MQTT');
    is($main::active_connections[0]->{state}, VALID_CONNECTION, 'Connection state is VALID');
};

subtest 'initMQTT with auth no TLS' => sub {
    reset_mocks();
    local $mqtt_config{username} = 'mqttuser';
    local $mqtt_config{password} = 'mqttpass';
    local $mqtt_config{tls_ca} = undef;
    local $mqtt_config{server} = 'localhost:1883';

    initMQTT();

    is(scalar @mqtt_simple_new_calls, 1, 'Net::MQTT::Simple->new called');
    is(scalar @mqtt_ssl_new_calls, 0, 'SSL not used without tls_ca');
    is(scalar @mqtt_login_calls, 1, 'login called with auth');
    is($mqtt_login_calls[0]->{user}, 'mqttuser', 'Correct username');
    is($mqtt_login_calls[0]->{pass}, 'mqttpass', 'Correct password');
};

subtest 'initMQTT with auth and TLS (CA only)' => sub {
    reset_mocks();
    local $mqtt_config{username} = 'mqttuser';
    local $mqtt_config{password} = 'mqttpass';
    local $mqtt_config{tls_ca} = '/path/to/ca.pem';
    local $mqtt_config{tls_cert} = undef;
    local $mqtt_config{tls_key} = undef;
    local $mqtt_config{server} = 'localhost:8883';

    initMQTT();

    is(scalar @mqtt_ssl_new_calls, 1, 'Net::MQTT::Simple::SSL->new called');
    is(scalar @mqtt_simple_new_calls, 0, 'Non-SSL not used with tls_ca');
    is($mqtt_ssl_new_calls[0]->{server}, 'localhost:8883', 'Correct server');
    is($mqtt_ssl_new_calls[0]->{sockopts}->{SSL_ca_file}, '/path/to/ca.pem', 'CA file set');
    ok(!exists $mqtt_ssl_new_calls[0]->{sockopts}->{SSL_cert_file}, 'No client cert');
    is(scalar @mqtt_login_calls, 1, 'login called');
};

subtest 'initMQTT with auth and TLS (client certs)' => sub {
    reset_mocks();
    local $mqtt_config{username} = 'mqttuser';
    local $mqtt_config{password} = 'mqttpass';
    local $mqtt_config{tls_ca} = '/path/to/ca.pem';
    local $mqtt_config{tls_cert} = '/path/to/client.pem';
    local $mqtt_config{tls_key} = '/path/to/client.key';
    local $mqtt_config{server} = 'localhost:8883';

    initMQTT();

    is(scalar @mqtt_ssl_new_calls, 1, 'SSL connection created');
    is($mqtt_ssl_new_calls[0]->{sockopts}->{SSL_ca_file}, '/path/to/ca.pem', 'CA file set');
    is($mqtt_ssl_new_calls[0]->{sockopts}->{SSL_cert_file}, '/path/to/client.pem', 'Client cert set');
    is($mqtt_ssl_new_calls[0]->{sockopts}->{SSL_key_file}, '/path/to/client.key', 'Client key set');
};

subtest 'initMQTT with TLS insecure mode' => sub {
    reset_mocks();
    local $mqtt_config{username} = 'mqttuser';
    local $mqtt_config{password} = 'mqttpass';
    local $mqtt_config{tls_ca} = '/path/to/ca.pem';
    local $mqtt_config{tls_insecure} = 1;
    local $mqtt_config{server} = 'localhost:8883';

    initMQTT();

    is($mqtt_ssl_new_calls[0]->{sockopts}->{SSL_verify_mode}, 0, 'SSL_VERIFY_NONE set for insecure mode');
};

subtest 'initMQTT handles connection failure' => sub {
    reset_mocks();
    $mqtt_new_return_value = undef;  # Simulate connection failure
    local $mqtt_config{username} = undef;
    local $mqtt_config{password} = undef;
    local $mqtt_config{server} = 'localhost:1883';

    initMQTT();

    # Even on failure, connection entry is added (with undef mqtt_conn)
    is(scalar @main::active_connections, 1, 'Connection entry still added on failure');
};

subtest 'initMQTT sets correct connection metadata' => sub {
    reset_mocks();
    local $mqtt_config{username} = undef;
    local $mqtt_config{password} = undef;
    local $mqtt_config{server} = 'localhost:1883';

    initMQTT();

    my $conn = $main::active_connections[0];
    is($conn->{type}, MQTT, 'type is MQTT');
    is($conn->{state}, VALID_CONNECTION, 'state is VALID_CONNECTION');
    is($conn->{monlist}, '', 'monlist is empty string');
    is($conn->{intlist}, '', 'intlist is empty string');
    ok(exists $conn->{last_sent}, 'last_sent hash exists');
    ok(exists $conn->{mqtt_conn}, 'mqtt_conn exists');
};

done_testing();

# Mock MQTT connection object
package MockMQTT;
sub new { bless {}, shift }
sub login {
    my ($self, $user, $pass) = @_;
    push @main::mqtt_login_calls, { user => $user, pass => $pass };
    return 1;
}
