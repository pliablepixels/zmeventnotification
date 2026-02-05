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

# Stub FCM and MQTT init functions
our $fcm_init_called = 0;
our $mqtt_init_called = 0;

BEGIN {
    for my $pkg (qw(
        ZmEventNotification::FCM
        ZmEventNotification::MQTT
    )) {
        (my $file = $pkg) =~ s{::}{/}g;
        $INC{"$file.pm"} = 1;
    }
    no strict 'refs';
    *{'ZmEventNotification::FCM::initFCMTokens'} = sub { $main::fcm_init_called = 1; };
    *{'ZmEventNotification::FCM::import'} = sub {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::initFCMTokens"} = \&ZmEventNotification::FCM::initFCMTokens;
    };
    *{'ZmEventNotification::MQTT::initMQTT'} = sub { $main::mqtt_init_called = 1; };
    *{'ZmEventNotification::MQTT::import'} = sub {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::initMQTT"} = \&ZmEventNotification::MQTT::initMQTT;
    };
}

use_ok('ZmEventNotification::Connection');
ZmEventNotification::Connection->import(':all');

# Helper to check if code runs without dying
sub lives_ok(&$) {
    my ($code, $desc) = @_;
    eval { $code->() };
    ok(!$@, $desc) or diag("Died: $@");
}

# ===== check_for_duplicate_token tests =====
subtest 'check_for_duplicate_token' => sub {
    # Setup connections with duplicate tokens
    @main::active_connections = (
        { token => 'abc123', type => FCM, state => VALID_CONNECTION },
        { token => 'abc123', type => FCM, state => VALID_CONNECTION },
        { token => 'xyz789', type => FCM, state => VALID_CONNECTION },
    );

    # Should not die or error, just log duplicates
    lives_ok { check_for_duplicate_token() } 'check_for_duplicate_token handles duplicates';

    # Test with no duplicates
    @main::active_connections = (
        { token => 'unique1', type => FCM, state => VALID_CONNECTION },
        { token => 'unique2', type => FCM, state => VALID_CONNECTION },
    );
    lives_ok { check_for_duplicate_token() } 'check_for_duplicate_token handles no duplicates';

    # Test with empty connections
    @main::active_connections = ();
    lives_ok { check_for_duplicate_token() } 'check_for_duplicate_token handles empty list';

    # Test with empty tokens
    @main::active_connections = (
        { token => '', type => FCM, state => VALID_CONNECTION },
        { token => '', type => FCM, state => VALID_CONNECTION },
    );
    lives_ok { check_for_duplicate_token() } 'check_for_duplicate_token ignores empty tokens';
};

# ===== checkConnection tests =====
subtest 'checkConnection removes PENDING_DELETE' => sub {
    @main::active_connections = (
        { token => 'tok1', type => FCM, state => VALID_CONNECTION },
        { token => 'tok2', type => FCM, state => PENDING_DELETE },
        { token => 'tok3', type => WEB, state => VALID_CONNECTION },
    );

    checkConnection();

    is(scalar @main::active_connections, 2, 'PENDING_DELETE connection removed');
    my @found = grep { $_->{token} eq 'tok2' } @main::active_connections;
    is(scalar @found, 0, 'tok2 was deleted');
};

subtest 'checkConnection times out PENDING_AUTH' => sub {
    # Create a mock connection object
    my $mock_conn = MockConn->new('192.168.1.100', 12345);

    @main::active_connections = (
        {
            token => 'tok_pending',
            type => WEB,
            state => PENDING_AUTH,
            time => time() - ($auth_config{timeout} + 10),  # Past timeout
            conn => $mock_conn,
        },
    );

    # After checkConnection, the timed-out connection should be removed
    # (it's marked PENDING_DELETE and then filtered out)
    checkConnection();

    is(scalar @main::active_connections, 0, 'PENDING_AUTH connection removed after timeout');
    ok($mock_conn->{disconnected}, 'Connection was disconnected');
};

subtest 'checkConnection keeps valid PENDING_AUTH within timeout' => sub {
    my $mock_conn = MockConn->new('192.168.1.101', 12346);

    @main::active_connections = (
        {
            token => 'tok_pending2',
            type => WEB,
            state => PENDING_AUTH,
            time => time() - 1,  # Only 1 second ago
            conn => $mock_conn,
        },
    );

    checkConnection();

    is($main::active_connections[0]->{state}, PENDING_AUTH, 'PENDING_AUTH connection kept within timeout');
};

subtest 'checkConnection counts connection types correctly' => sub {
    @main::active_connections = (
        { token => 'fcm1', type => FCM, state => VALID_CONNECTION },
        { token => 'fcm2', type => FCM, state => VALID_CONNECTION },
        { token => 'fcm3', type => FCM, state => INVALID_CONNECTION },
        { token => 'web1', type => WEB, state => VALID_CONNECTION },
        { token => 'web2', type => WEB, state => INVALID_CONNECTION },
        { token => '', type => MQTT, state => VALID_CONNECTION },
        { token => 'pend', type => WEB, state => PENDING_AUTH, time => time(), conn => MockConn->new('1.2.3.4', 1234) },
        { token => 'ctrl', type => WEB, state => VALID_CONNECTION, category => 'escontrol' },
    );

    lives_ok { checkConnection() } 'checkConnection counts without error';
};

# ===== loadPredefinedConnections tests =====
subtest 'loadPredefinedConnections calls FCM init when enabled' => sub {
    $fcm_init_called = 0;
    $mqtt_init_called = 0;
    local $fcm_config{enabled} = 1;
    local $mqtt_config{enabled} = 0;

    loadPredefinedConnections();

    is($fcm_init_called, 1, 'FCM init called when enabled');
    is($mqtt_init_called, 0, 'MQTT init not called when disabled');
};

subtest 'loadPredefinedConnections calls MQTT init when enabled' => sub {
    $fcm_init_called = 0;
    $mqtt_init_called = 0;
    local $fcm_config{enabled} = 0;
    local $mqtt_config{enabled} = 1;

    loadPredefinedConnections();

    is($fcm_init_called, 0, 'FCM init not called when disabled');
    is($mqtt_init_called, 1, 'MQTT init called when enabled');
};

subtest 'loadPredefinedConnections calls both when both enabled' => sub {
    $fcm_init_called = 0;
    $mqtt_init_called = 0;
    local $fcm_config{enabled} = 1;
    local $mqtt_config{enabled} = 1;

    loadPredefinedConnections();

    is($fcm_init_called, 1, 'FCM init called');
    is($mqtt_init_called, 1, 'MQTT init called');
};

subtest 'loadPredefinedConnections calls neither when both disabled' => sub {
    $fcm_init_called = 0;
    $mqtt_init_called = 0;
    local $fcm_config{enabled} = 0;
    local $mqtt_config{enabled} = 0;

    loadPredefinedConnections();

    is($fcm_init_called, 0, 'FCM init not called');
    is($mqtt_init_called, 0, 'MQTT init not called');
};

done_testing();

# Mock connection class
package MockConn;
sub new {
    my ($class, $ip, $port) = @_;
    return bless { ip => $ip, port => $port, sent => [], disconnected => 0 }, $class;
}
sub ip   { shift->{ip} }
sub port { shift->{port} }
sub send_utf8 {
    my ($self, $msg) = @_;
    push @{$self->{sent}}, $msg;
}
sub disconnect { shift->{disconnected} = 1 }
