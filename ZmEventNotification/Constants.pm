package ZmEventNotification::Constants;

use strict;
use warnings;
use Exporter 'import';

# Connection states
use constant {
  PENDING_AUTH       => 1,
  VALID_CONNECTION   => 2,
  INVALID_CONNECTION => 3,
  PENDING_DELETE     => 4,
};

# Connection types
use constant {
  FCM  => 1000,
  MQTT => 1001,
  WEB  => 1002
};

# escontrol notification states
use constant {
  ESCONTROL_FORCE_NOTIFY   => 1,
  ESCONTROL_DEFAULT_NOTIFY => 0,
  ESCONTROL_FORCE_MUTE     => -1,
};

# App defaults
use constant {
  DEFAULT_CONFIG_FILE        => '/etc/zm/zmeventnotification.yml',
  DEFAULT_PORT               => 9000,
  DEFAULT_ADDRESS            => '[::]',
  DEFAULT_AUTH_ENABLE        => 'yes',
  DEFAULT_AUTH_TIMEOUT       => 20,
  DEFAULT_FCM_ENABLE         => 'yes',
  DEFAULT_USE_FCMV1          => 'yes',
  DEFAULT_REPLACE_PUSH_MSGS  => 'no',
  DEFAULT_MQTT_ENABLE        => 'no',
  DEFAULT_MQTT_SERVER        => '127.0.0.1',
  DEFAULT_MQTT_TOPIC         => 'zoneminder',
  DEFAULT_MQTT_TICK_INTERVAL => 15,
  DEFAULT_MQTT_RETAIN        => 'no',
  DEFAULT_FCM_TOKEN_FILE     => '/var/lib/zmeventnotification/push/tokens.txt',

  DEFAULT_USE_API_PUSH => 'no',

  DEFAULT_BASE_DATA_PATH => '/var/lib/zmeventnotification',
  DEFAULT_SSL_ENABLE     => 'yes',

  DEFAULT_CUSTOMIZE_VERBOSE                       => 'no',
  DEFAULT_CUSTOMIZE_EVENT_CHECK_INTERVAL          => 5,
  DEFAULT_CUSTOMIZE_ES_DEBUG_LEVEL                => 5,
  DEFAULT_CUSTOMIZE_MONITOR_RELOAD_INTERVAL       => 300,
  DEFAULT_CUSTOMIZE_READ_ALARM_CAUSE              => 'no',
  DEFAULT_CUSTOMIZE_TAG_ALARM_EVENT_ID            => 'no',
  DEFAULT_CUSTOMIZE_USE_CUSTOM_NOTIFICATION_SOUND => 'no',
  DEFAULT_CUSTOMIZE_INCLUDE_PICTURE               => 'no',

  DEFAULT_USE_HOOKS                          => 'no',
  DEFAULT_HOOK_KEEP_FRAME_MATCH_TYPE         => 'yes',
  DEFAULT_HOOK_USE_HOOK_DESCRIPTION          => 'no',
  DEFAULT_HOOK_STORE_FRAME_IN_ZM             => 'no',
  DEFAULT_RESTART_INTERVAL                   => 7200,
  DEFAULT_EVENT_START_NOTIFY_ON_HOOK_FAIL    => 'none',
  DEFAULT_EVENT_START_NOTIFY_ON_HOOK_SUCCESS => 'none',
  DEFAULT_EVENT_END_NOTIFY_ON_HOOK_FAIL      => 'none',
  DEFAULT_EVENT_END_NOTIFY_ON_HOOK_SUCCESS   => 'none',
  DEFAULT_EVENT_END_NOTIFY_IF_START_SUCCESS  => 'yes',
  DEFAULT_SEND_EVENT_START_NOTIFICATION      => 'yes',
  DEFAULT_SEND_EVENT_END_NOTIFICATION        => 'no',

  DEFAULT_USE_ESCONTROL_INTERFACE            => 'no',
  DEFAULT_ESCONTROL_INTERFACE_FILE =>
    '/var/lib/zmeventnotification/misc/escontrol_interface.dat',
  DEFAULT_FCM_DATE_FORMAT => '%I:%M %p, %d-%b',
  DEFAULT_FCM_ANDROID_PRIORITY => 'high',
  DEFAULT_FCM_LOG_RAW_MESSAGE  => 'no',
  DEFAULT_FCM_LOG_MESSAGE_ID   => 'NONE',
  DEFAULT_MAX_FCM_PER_MONTH_PER_TOKEN => 8000,
  DEFAULT_FCM_V1_KEY => 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJnZW5lcmF0b3IiOiJwbGlhYmxlIHBpeGVscyIsImlhdCI6MTcyNzQ0OTI1MCwiY2xpZW50Ijoiem1uaW5qYSJ9.2to4a_X0EQ8MtXyNzVCHfftn6zDn6QpwlSjVYicUq8I',
  DEFAULT_FCM_V1_URL => 'https://us-central1-zoneminder-ninja.cloudfunctions.net/send_push',
  DEFAULT_MAX_PARALLEL_HOOKS => 0,
  DEFAULT_HOOK_TAG_DETECTED_OBJECTS => 'no',
};

# Auto-export all symbols -- this is a constants-only module,
# so there's nothing to hide. No need to maintain a hand-written list.
our @EXPORT_OK;
our %EXPORT_TAGS;
BEGIN {
  no strict 'refs';
  @EXPORT_OK = grep { defined &{"${_}"} } keys %{__PACKAGE__ . '::'};
  %EXPORT_TAGS = ( all => \@EXPORT_OK );
}

1;
