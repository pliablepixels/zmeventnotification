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

require StubZM;

use ZmEventNotification::Config qw(:all);
use ZmEventNotification::Constants qw(:all);

# Load config
my $fixtures = File::Spec->catdir($FindBin::Bin, 'fixtures');
my $cfg = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_es.yml'));
my $sec = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_secrets.yml'));
$ZmEventNotification::Config::secrets = $sec;
loadEsConfigSettings($cfg);

# Track calls to stubbed functions
our @save_fcm_tokens_calls;
our @save_escontrol_calls;
our @load_esconfig_calls;
our @restart_es_calls;

# Override main:: functions
sub main::saveEsControlSettings { push @save_escontrol_calls, 1; }
sub main::loadEsConfigSettings { push @load_esconfig_calls, 1; }
sub main::restartES { push @restart_es_calls, 1; }

# Stub FCM and DB
BEGIN {
    for my $pkg (qw(ZmEventNotification::FCM ZmEventNotification::DB)) {
        (my $file = $pkg) =~ s{::}{/}g;
        $INC{"$file.pm"} = 1;
    }
    no strict 'refs';
    *{'ZmEventNotification::FCM::saveFCMTokens'} = sub {
        my @args = @_;
        push @main::save_fcm_tokens_calls, \@args;
        return ($args[1], $args[2]);  # Return monlist, intlist
    };
    *{'ZmEventNotification::FCM::import'} = sub {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::saveFCMTokens"} = \&ZmEventNotification::FCM::saveFCMTokens;
    };
    *{'ZmEventNotification::DB::getAllMonitorIds'} = sub { return (1, 2, 3); };
    *{'ZmEventNotification::DB::import'} = sub {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::getAllMonitorIds"} = \&ZmEventNotification::DB::getAllMonitorIds;
    };
}

# Mock database for auth
our $mock_db_password;
our $mock_db_user_exists = 1;
our $dbh;

BEGIN {
    package MockDBH;
    sub prepare_cached {
        my ($self, $sql) = @_;
        return MockSTH->new($sql);
    }

    package MockSTH;
    sub new {
        my ($class, $sql) = @_;
        return bless { sql => $sql }, $class;
    }
    sub execute { 1 }
    sub finish { 1 }
    sub fetchrow_hashref {
        return undef unless $main::mock_db_user_exists;
        return { Password => $main::mock_db_password };
    }
}

$main::dbh = bless {}, 'MockDBH';

use_ok('ZmEventNotification::WebSocketHandler');
ZmEventNotification::WebSocketHandler->import(':all');

# Reset test state
sub reset_state {
    @save_fcm_tokens_calls = ();
    @save_escontrol_calls = ();
    @load_esconfig_calls = ();
    @restart_es_calls = ();
    @main::active_connections = ();
    %main::monitors = (
        1 => { Id => 1, Name => 'Front' },
        2 => { Id => 2, Name => 'Back' },
        3 => { Id => 3, Name => 'Side' },
    );
    %escontrol_interface_settings = ( notifications => {} );
}

# ===== getNotificationStatusEsControl tests =====
subtest 'getNotificationStatusEsControl' => sub {
    reset_state();

    # Monitor not in settings -> FORCE_NOTIFY
    is(getNotificationStatusEsControl(99), ESCONTROL_FORCE_NOTIFY, 'Unknown monitor returns FORCE_NOTIFY');

    # Monitor in settings
    $escontrol_interface_settings{notifications}{1} = ESCONTROL_FORCE_MUTE;
    is(getNotificationStatusEsControl(1), ESCONTROL_FORCE_MUTE, 'Returns setting for known monitor');

    $escontrol_interface_settings{notifications}{2} = ESCONTROL_DEFAULT_NOTIFY;
    is(getNotificationStatusEsControl(2), ESCONTROL_DEFAULT_NOTIFY, 'Returns DEFAULT for monitor 2');
};

# ===== populateEsControlNotification tests =====
subtest 'populateEsControlNotification' => sub {
    reset_state();
    local $escontrol_config{enabled} = 1;

    populateEsControlNotification();

    # Should have added entries for monitors 1, 2, 3
    ok(exists $escontrol_interface_settings{notifications}{1}, 'Monitor 1 added');
    ok(exists $escontrol_interface_settings{notifications}{2}, 'Monitor 2 added');
    ok(exists $escontrol_interface_settings{notifications}{3}, 'Monitor 3 added');
    is($escontrol_interface_settings{notifications}{1}, ESCONTROL_DEFAULT_NOTIFY, 'Default notification state');
    is(scalar @save_escontrol_calls, 1, 'Settings saved');
};

subtest 'populateEsControlNotification disabled' => sub {
    reset_state();
    local $escontrol_config{enabled} = 0;

    populateEsControlNotification();

    # Should not add anything when disabled
    ok(!exists $escontrol_interface_settings{notifications}{1}, 'Nothing added when disabled');
};

subtest 'populateEsControlNotification does not overwrite existing' => sub {
    reset_state();
    local $escontrol_config{enabled} = 1;
    $escontrol_interface_settings{notifications}{1} = ESCONTROL_FORCE_MUTE;

    populateEsControlNotification();

    # Should keep existing setting for monitor 1
    is($escontrol_interface_settings{notifications}{1}, ESCONTROL_FORCE_MUTE, 'Existing setting preserved');
};

# ===== validateAuth tests =====
subtest 'validateAuth - auth disabled' => sub {
    reset_state();
    local $auth_config{enabled} = 0;

    is(validateAuth('anyuser', 'anypass', 'normal'), 1, 'Returns 1 when auth disabled');
};

subtest 'validateAuth - empty credentials' => sub {
    reset_state();
    local $auth_config{enabled} = 1;

    is(validateAuth('', 'pass', 'normal'), 0, 'Returns 0 for empty username');
    is(validateAuth('user', '', 'normal'), 0, 'Returns 0 for empty password');
    is(validateAuth('', '', 'normal'), 0, 'Returns 0 for both empty');
};

subtest 'validateAuth - user not found' => sub {
    reset_state();
    local $auth_config{enabled} = 1;
    $mock_db_user_exists = 0;

    is(validateAuth('unknown', 'pass', 'normal'), 0, 'Returns 0 for unknown user');
    $mock_db_user_exists = 1;
};

subtest 'validateAuth - escontrol category' => sub {
    reset_state();
    local $escontrol_config{enabled} = 1;
    local $escontrol_config{password} = 'adminpass';

    is(validateAuth('admin', 'adminpass', 'escontrol'), 1, 'Correct escontrol password');
    ok(!validateAuth('admin', 'wrongpass', 'escontrol'), 'Wrong escontrol password');
};

subtest 'validateAuth - escontrol disabled' => sub {
    reset_state();
    local $escontrol_config{enabled} = 0;
    local $escontrol_config{password} = 'adminpass';

    is(validateAuth('admin', 'adminpass', 'escontrol'), 0, 'Returns 0 when escontrol disabled');
};

# ===== processIncomingMessage tests =====
subtest 'processIncomingMessage - malformed JSON' => sub {
    reset_state();
    my $mock_conn = MockConn->new('192.168.1.1', 12345);

    processIncomingMessage($mock_conn, 'not valid json');

    is(scalar @{$mock_conn->{sent}}, 1, 'Response sent');
    my $response = decode_json($mock_conn->{sent}[0]);
    is($response->{event}, 'malformed', 'Event is malformed');
    is($response->{reason}, 'BADJSON', 'Reason is BADJSON');
};

subtest 'processIncomingMessage - push event when disabled' => sub {
    reset_state();
    local $fcm_config{enabled} = 0;
    my $mock_conn = MockConn->new('192.168.1.1', 12345);

    my $msg = encode_json({ event => 'push', data => { type => 'token' } });
    processIncomingMessage($mock_conn, $msg);

    is(scalar @{$mock_conn->{sent}}, 1, 'Response sent');
    my $response = decode_json($mock_conn->{sent}[0]);
    is($response->{event}, 'push', 'Event is push');
    is($response->{reason}, 'PUSHDISABLED', 'Reason is PUSHDISABLED');
};

subtest 'processIncomingMessage - escontrol when disabled' => sub {
    reset_state();
    local $escontrol_config{enabled} = 0;
    my $mock_conn = MockConn->new('192.168.1.1', 12345);

    my $msg = encode_json({ event => 'escontrol', data => { command => 'get' } });
    processIncomingMessage($mock_conn, $msg);

    my $response = decode_json($mock_conn->{sent}[0]);
    is($response->{event}, 'escontrol', 'Event is escontrol');
    is($response->{reason}, 'ESCONTROLDISABLED', 'Reason is ESCONTROLDISABLED');
};

subtest 'processIncomingMessage - unsupported event' => sub {
    reset_state();
    my $mock_conn = MockConn->new('192.168.1.1', 12345);

    my $msg = encode_json({ event => 'unknownevent', data => {} });
    processIncomingMessage($mock_conn, $msg);

    my $response = decode_json($mock_conn->{sent}[0]);
    is($response->{event}, 'unknownevent', 'Event echoed back');
    is($response->{reason}, 'NOTSUPPORTED', 'Reason is NOTSUPPORTED');
};

subtest 'processIncomingMessage - control filter missing monlist' => sub {
    reset_state();
    my $mock_conn = MockConn->new('192.168.1.1', 12345);
    @main::active_connections = (
        { conn => $mock_conn, state => VALID_CONNECTION, type => WEB },
    );

    my $msg = encode_json({ event => 'control', data => { type => 'filter', intlist => '0,0' } });
    processIncomingMessage($mock_conn, $msg);

    my $response = decode_json($mock_conn->{sent}[0]);
    is($response->{event}, 'control', 'Event is control');
    is($response->{reason}, 'MISSINGMONITORLIST', 'Reason is MISSINGMONITORLIST');
};

subtest 'processIncomingMessage - control filter missing intlist' => sub {
    reset_state();
    my $mock_conn = MockConn->new('192.168.1.1', 12345);
    @main::active_connections = (
        { conn => $mock_conn, state => VALID_CONNECTION, type => WEB },
    );

    my $msg = encode_json({ event => 'control', data => { type => 'filter', monlist => '1,2' } });
    processIncomingMessage($mock_conn, $msg);

    my $response = decode_json($mock_conn->{sent}[0]);
    is($response->{reason}, 'MISSINGINTERVALLIST', 'Reason is MISSINGINTERVALLIST');
};

subtest 'processIncomingMessage - control version' => sub {
    reset_state();
    local $main::app_version = '7.0.0';
    my $mock_conn = MockConn->new('192.168.1.1', 12345);
    @main::active_connections = (
        { conn => $mock_conn, state => VALID_CONNECTION, type => WEB },
    );

    my $msg = encode_json({ event => 'control', data => { type => 'version' } });
    processIncomingMessage($mock_conn, $msg);

    my $response = decode_json($mock_conn->{sent}[0]);
    is($response->{event}, 'control', 'Event is control');
    is($response->{type}, 'version', 'Type is version');
    is($response->{status}, 'Success', 'Status is Success');
    is($response->{version}, '7.0.0', 'Version returned');
};

subtest 'processIncomingMessage - auth success' => sub {
    reset_state();
    local $auth_config{enabled} = 0;  # Disable auth for easy testing
    local $main::app_version = '7.0.0';
    my $mock_conn = MockConn->new('192.168.1.1', 12345);
    @main::active_connections = (
        { conn => $mock_conn, state => PENDING_AUTH, type => WEB, token => '' },
    );

    my $msg = encode_json({
        event => 'auth',
        data => { user => 'testuser', password => 'testpass', monlist => '1,2', intlist => '0,0' }
    });
    processIncomingMessage($mock_conn, $msg);

    my $response = decode_json($mock_conn->{sent}[0]);
    is($response->{event}, 'auth', 'Event is auth');
    is($response->{status}, 'Success', 'Auth successful');
    is($main::active_connections[0]->{state}, VALID_CONNECTION, 'State updated to VALID');
    is($main::active_connections[0]->{monlist}, '1,2', 'Monlist stored');
};

subtest 'processIncomingMessage - auth failure' => sub {
    reset_state();
    local $auth_config{enabled} = 1;
    $mock_db_user_exists = 0;
    my $mock_conn = MockConn->new('192.168.1.1', 12345);
    @main::active_connections = (
        { conn => $mock_conn, state => PENDING_AUTH, type => WEB, token => '' },
    );

    my $msg = encode_json({
        event => 'auth',
        data => { user => 'baduser', password => 'badpass' }
    });
    processIncomingMessage($mock_conn, $msg);

    my $response = decode_json($mock_conn->{sent}[0]);
    is($response->{status}, 'Fail', 'Auth failed');
    is($response->{reason}, 'BADAUTH', 'Reason is BADAUTH');
    is($main::active_connections[0]->{state}, PENDING_DELETE, 'State set to PENDING_DELETE');
    $mock_db_user_exists = 1;
};

# ===== processEsControlCommand tests =====
subtest 'processEsControlCommand - get' => sub {
    reset_state();
    local $escontrol_config{enabled} = 1;
    $escontrol_interface_settings{notifications}{1} = ESCONTROL_FORCE_MUTE;

    my $mock_conn = MockConn->new('192.168.1.1', 12345);
    @main::active_connections = (
        { conn => $mock_conn, state => VALID_CONNECTION, type => WEB, category => 'escontrol' },
    );

    my $json = { event => 'escontrol', data => { command => 'get' } };
    processEsControlCommand($json, $mock_conn);

    my $response = decode_json($mock_conn->{sent}[0]);
    is($response->{status}, 'Success', 'Get command successful');
    ok($response->{response}, 'Response contains settings');
};

subtest 'processEsControlCommand - mute' => sub {
    reset_state();
    local $escontrol_config{enabled} = 1;
    $escontrol_interface_settings{notifications}{1} = ESCONTROL_DEFAULT_NOTIFY;

    my $mock_conn = MockConn->new('192.168.1.1', 12345);
    @main::active_connections = (
        { conn => $mock_conn, state => VALID_CONNECTION, type => WEB, category => 'escontrol' },
    );

    my $json = { event => 'escontrol', data => { command => 'mute', monitors => [1, 2] } };
    processEsControlCommand($json, $mock_conn);

    is($escontrol_interface_settings{notifications}{1}, ESCONTROL_FORCE_MUTE, 'Monitor 1 muted');
    is($escontrol_interface_settings{notifications}{2}, ESCONTROL_FORCE_MUTE, 'Monitor 2 muted');
    is(scalar @save_escontrol_calls, 1, 'Settings saved');
};

subtest 'processEsControlCommand - unmute' => sub {
    reset_state();
    local $escontrol_config{enabled} = 1;
    $escontrol_interface_settings{notifications}{1} = ESCONTROL_FORCE_MUTE;

    my $mock_conn = MockConn->new('192.168.1.1', 12345);
    @main::active_connections = (
        { conn => $mock_conn, state => VALID_CONNECTION, type => WEB, category => 'escontrol' },
    );

    my $json = { event => 'escontrol', data => { command => 'unmute', monitors => [1] } };
    processEsControlCommand($json, $mock_conn);

    is($escontrol_interface_settings{notifications}{1}, ESCONTROL_FORCE_NOTIFY, 'Monitor 1 unmuted');
};

subtest 'processEsControlCommand - not escontrol category' => sub {
    reset_state();
    local $escontrol_config{enabled} = 1;

    my $mock_conn = MockConn->new('192.168.1.1', 12345);
    @main::active_connections = (
        { conn => $mock_conn, state => VALID_CONNECTION, type => WEB, category => 'normal' },
    );

    my $json = { event => 'escontrol', data => { command => 'get' } };
    processEsControlCommand($json, $mock_conn);

    my $response = decode_json($mock_conn->{sent}[0]);
    is($response->{status}, 'Fail', 'Command failed');
    is($response->{reason}, 'NOTCONTROL', 'Reason is NOTCONTROL');
};

subtest 'processEsControlCommand - restart' => sub {
    reset_state();
    local $escontrol_config{enabled} = 1;

    my $mock_conn = MockConn->new('192.168.1.1', 12345);
    @main::active_connections = (
        { conn => $mock_conn, state => VALID_CONNECTION, type => WEB, category => 'escontrol' },
    );

    my $json = { event => 'escontrol', data => { command => 'restart' } };
    processEsControlCommand($json, $mock_conn);

    my $response = decode_json($mock_conn->{sent}[0]);
    is($response->{status}, 'Success', 'Restart command successful');
    is(scalar @restart_es_calls, 1, 'restartES called');
};

subtest 'processEsControlCommand - reset' => sub {
    reset_state();
    local $escontrol_config{enabled} = 1;
    $escontrol_interface_settings{notifications}{1} = ESCONTROL_FORCE_MUTE;

    my $mock_conn = MockConn->new('192.168.1.1', 12345);
    @main::active_connections = (
        { conn => $mock_conn, state => VALID_CONNECTION, type => WEB, category => 'escontrol' },
    );

    my $json = { event => 'escontrol', data => { command => 'reset' } };
    processEsControlCommand($json, $mock_conn);

    my $response = decode_json($mock_conn->{sent}[0]);
    is($response->{status}, 'Success', 'Reset command successful');
    is(scalar @load_esconfig_calls, 1, 'loadEsConfigSettings called');
};

subtest 'processEsControlCommand - unsupported command' => sub {
    reset_state();
    local $escontrol_config{enabled} = 1;

    my $mock_conn = MockConn->new('192.168.1.1', 12345);
    @main::active_connections = (
        { conn => $mock_conn, state => VALID_CONNECTION, type => WEB, category => 'escontrol' },
    );

    my $json = { event => 'escontrol', data => { command => 'invalid' } };
    processEsControlCommand($json, $mock_conn);

    my $response = decode_json($mock_conn->{sent}[0]);
    is($response->{status}, 'Fail', 'Invalid command fails');
    is($response->{reason}, 'NOTSUPPORTED', 'Reason is NOTSUPPORTED');
};

done_testing();

# Mock connection class
package MockConn;
sub new {
    my ($class, $ip, $port) = @_;
    return bless { ip => $ip, port => $port, sent => [] }, $class;
}
sub ip   { shift->{ip} }
sub port { shift->{port} }
sub send_utf8 {
    my ($self, $msg) = @_;
    push @{$self->{sent}}, $msg;
}
