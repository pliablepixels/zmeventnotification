#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../";
use lib "$FindBin::Bin/lib";

use Test::More;
use JSON;
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

# Stub out heavy deps
for my $pkg (qw(
    ZmEventNotification::FCM
    ZmEventNotification::MQTT
    ZmEventNotification::DB
    ZmEventNotification::WebSocketHandler
)) {
    (my $file = $pkg) =~ s{::}{/}g;
    $INC{"$file.pm"} = 1;
    no strict 'refs';
    *{"${pkg}::import"} = sub { 1 };
    if ($pkg eq 'ZmEventNotification::FCM') {
        *{"${pkg}::sendOverFCM"} = sub { };
    } elsif ($pkg eq 'ZmEventNotification::MQTT') {
        *{"${pkg}::sendOverMQTTBroker"} = sub { };
    } elsif ($pkg eq 'ZmEventNotification::DB') {
        *{"${pkg}::updateEventinZmDB"} = sub { };
        *{"${pkg}::getNotesFromEventDB"} = sub { '' };
        *{"${pkg}::tagEventObjects"} = sub { };
    } elsif ($pkg eq 'ZmEventNotification::WebSocketHandler') {
        *{"${pkg}::getNotificationStatusEsControl"} = sub { 0 };
    }
}

use_ok('ZmEventNotification::HookProcessor');
ZmEventNotification::HookProcessor->import(':all');

# Set up WRITER
my $pipe_output = '';
open(my $writer_fh, '>', \$pipe_output) or die "Cannot open scalar ref: $!";
$writer_fh->autoflush(1);
*main::WRITER = *$writer_fh;

# Mock connection object with ip()/port()
{
    package MockConn;
    sub new  { bless {}, shift }
    sub ip   { '192.168.1.100' }
    sub port { 9000 }
}

my $mock_conn = MockConn->new();

my $alarm_base = {
    MonitorId => '3',
    EventId   => '999',
    Name      => 'Backyard',
    Cause     => '[a] detected:dog,cat',
};

# ===== Test: Pipe line format =====
{
    $pipe_output = '';
    my $ac = { id => 77, type => WEB, conn => $mock_conn, state => VALID_CONNECTION };
    sendOverWebSocket({ %$alarm_base }, $ac, 'event_start', 0);

    like($pipe_output, qr/^message--TYPE--77--SPLIT--/, 'pipe line: message--TYPE--ID--SPLIT--JSON');
}

# ===== Test: JSON envelope =====
{
    $pipe_output = '';
    my $ac = { id => 78, type => WEB, conn => $mock_conn, state => VALID_CONNECTION };
    sendOverWebSocket({ %$alarm_base }, $ac, 'event_start', 0);

    my ($header, $json_str) = split(/--SPLIT--/, $pipe_output, 2);
    chomp $json_str;
    my $data = decode_json($json_str);
    is($data->{event}, 'alarm', 'envelope event=alarm');
    is($data->{type}, '', 'envelope type is empty');
    is($data->{status}, 'Success', 'envelope status=Success');
    ok(ref $data->{events} eq 'ARRAY', 'events is array');
}

# ===== Test: events[0] content =====
{
    $pipe_output = '';
    my $ac = { id => 79, type => WEB, conn => $mock_conn, state => VALID_CONNECTION };
    sendOverWebSocket({ %$alarm_base }, $ac, 'event_start', 0);

    my (undef, $json_str) = split(/--SPLIT--/, $pipe_output, 2);
    chomp $json_str;
    my $data = decode_json($json_str);
    my $ev = $data->{events}[0];
    is($ev->{Name}, 'Backyard', 'events[0] has Name');
    is($ev->{MonitorId}, '3', 'events[0] has MonitorId');
    is($ev->{EventId}, '999', 'events[0] has EventId');
}

# ===== Test: event_end Cause prefix =====
{
    $pipe_output = '';
    my $ac = { id => 80, type => WEB, conn => $mock_conn, state => VALID_CONNECTION };
    sendOverWebSocket({ %$alarm_base }, $ac, 'event_end', 0);

    my (undef, $json_str) = split(/--SPLIT--/, $pipe_output, 2);
    chomp $json_str;
    my $data = decode_json($json_str);
    like($data->{events}[0]{Cause}, qr/^End:/, 'event_end: Cause prefixed with End:');
}

# ===== Test: Picture URL included when configured =====
{
    $pipe_output = '';
    local $notify_config{picture_url} = 'http://example.com/snap?eid=EVENTID&fid=BESTMATCH';
    local $notify_config{include_picture} = 1;
    my $ac = { id => 81, type => WEB, conn => $mock_conn, state => VALID_CONNECTION };
    sendOverWebSocket({ %$alarm_base }, $ac, 'event_start', 0);

    my (undef, $json_str) = split(/--SPLIT--/, $pipe_output, 2);
    chomp $json_str;
    my $data = decode_json($json_str);
    ok(defined $data->{events}[0]{Picture}, 'Picture URL included when configured');
}

# ===== Test: Picture URL excluded when not configured =====
{
    $pipe_output = '';
    local $notify_config{picture_url} = undef;
    local $notify_config{include_picture} = 0;
    my $ac = { id => 82, type => WEB, conn => $mock_conn, state => VALID_CONNECTION };
    sendOverWebSocket({ %$alarm_base }, $ac, 'event_start', 0);

    my (undef, $json_str) = split(/--SPLIT--/, $pipe_output, 2);
    chomp $json_str;
    my $data = decode_json($json_str);
    ok(!defined $data->{events}[0]{Picture}, 'Picture URL excluded when not configured');
}

done_testing();
