#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../";
use lib "$FindBin::Bin/lib";

use Test::More;

# Load stubs at compile time before Constants tries to export
BEGIN { require StubZM }

use ZmEventNotification::Constants qw(:all);

# --- Connection states ---
is(PENDING_AUTH,       1, 'PENDING_AUTH == 1');
is(VALID_CONNECTION,   2, 'VALID_CONNECTION == 2');
is(INVALID_CONNECTION, 3, 'INVALID_CONNECTION == 3');
is(PENDING_DELETE,     4, 'PENDING_DELETE == 4');

# --- Connection types ---
is(FCM,  1000, 'FCM == 1000');
is(MQTT, 1001, 'MQTT == 1001');
is(WEB,  1002, 'WEB == 1002');

# --- escontrol states ---
is(ESCONTROL_FORCE_NOTIFY,   1,  'ESCONTROL_FORCE_NOTIFY == 1');
is(ESCONTROL_DEFAULT_NOTIFY, 0,  'ESCONTROL_DEFAULT_NOTIFY == 0');
is(ESCONTROL_FORCE_MUTE,     -1, 'ESCONTROL_FORCE_MUTE == -1');

# --- App defaults ---
is(DEFAULT_CONFIG_FILE, '/etc/zm/zmeventnotification.yml', 'DEFAULT_CONFIG_FILE path');
is(DEFAULT_PORT,        9000,                              'DEFAULT_PORT == 9000');
is(DEFAULT_ADDRESS,     '[::]',                            'DEFAULT_ADDRESS');
is(DEFAULT_BASE_DATA_PATH, '/var/lib/zmeventnotification', 'DEFAULT_BASE_DATA_PATH');

# Verify some boolean defaults are strings
is(DEFAULT_AUTH_ENABLE, 'yes', 'DEFAULT_AUTH_ENABLE is yes');
is(DEFAULT_MQTT_ENABLE, 'no', 'DEFAULT_MQTT_ENABLE is no');

done_testing();
