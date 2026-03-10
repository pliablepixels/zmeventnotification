package ZmEventNotification::Config;

use strict;
use warnings;
use Storable qw(store retrieve);
use JSON;
use YAML::XS;
use File::Spec;
use Exporter 'import';
use ZmEventNotification::Constants qw(:all);

# Functions exported by default (used everywhere)
our @EXPORT = qw(
  config_get_val
  loadEsConfigSettings
  loadEsControlSettings
  saveEsControlSettings
  print_config
);

our @EXPORT_OK = qw(
  $config_obj $secrets $secrets_filename
  %server_config %auth_config %ssl_config
  %fcm_config %mqtt_config %push_config
  %hooks_config %notify_config %escontrol_config
  %escontrol_interface_settings %es_rules
);

our %EXPORT_TAGS = ( all => [ @EXPORT, @EXPORT_OK ] );

# Bootstrap scalars
our $config_obj;
our $secrets;
our $secrets_filename;

# Grouped config hashes
our %server_config = ();
our %auth_config = ();
our %ssl_config = ();
our %fcm_config = (
  cached_access_token        => undef,
  cached_access_token_expiry => 0,
);
our %mqtt_config = ();
our %push_config = ();
our %hooks_config = (
  max_parallel_hooks => 0,
);
our %notify_config = (
  es_debug_level => 2,
);
our %escontrol_config = ();

# Runtime state
our %escontrol_interface_settings = ( notifications => {} );

# Rules (loaded from YAML)
our %es_rules;

sub config_get_val {
  my ( $cfg, $sect, $parm, $def ) = @_;
  my $val = defined($cfg->{$sect}) ? $cfg->{$sect}{$parm} : undef;

  my $final_val = defined($val) ? "$val" : $def;
  if ($final_val) {
    my $first_char = substr( $final_val, 0, 1 );
    if ($first_char eq '!') {
      my $token = substr($final_val, 1);
      main::Debug(2, 'Got secret token !' . $token);
      main::Fatal('No secret file found') if !$secrets;
      my $secret_val = $secrets->{secrets}{$token};
      main::Fatal('Token:'.$token.' not found in secret file') if !$secret_val;
      $final_val = $secret_val;
    }
  }

  if ( exists $escontrol_interface_settings{$parm} ) {
    main::Debug(2, "ESCONTROL_INTERFACE overrides key: $parm with "
        . $escontrol_interface_settings{$parm});
    $final_val = $escontrol_interface_settings{$parm};
  }

  return $final_val if !defined($final_val);

  if    ( lc($final_val) eq 'yes' ) { $final_val = 1; }
  elsif ( lc($final_val) eq 'no' )  { $final_val = 0; }

  # ${template} substitution
  my @matches = ( $final_val =~ /\$\{(.*?)\}/g );
  foreach my $token (@matches) {
    my $tval = defined($cfg->{general}) ? $cfg->{general}{$token} : undef;
    $tval = $cfg->{$sect}{$token} if !$tval && defined($cfg->{$sect});
    next if !defined($tval);
    main::Debug(2, "config string substitution: \${$token} is '$tval'");
    $final_val =~ s/\$\{$token\}/$tval/g;
  }

  $final_val =~ s/^\s+|\s+$//g;   # trim
  return $final_val;
}

sub loadEsConfigSettings {
  my $cfg = shift // $config_obj;
  main::Fatal('loadEsConfigSettings called without a config object') unless $cfg;

  # --- server_config ---
  $server_config{restart_interval} = config_get_val($cfg, 'general', 'restart_interval',
    DEFAULT_RESTART_INTERVAL);
  if ( !$server_config{restart_interval} ) {
    main::Debug(1, 'ES will not be restarted as interval is specified as 0');
  } else {
    main::Debug(1, "ES will be restarted at $server_config{restart_interval} seconds");
  }
  $server_config{skip_monitors} = config_get_val($cfg, 'general', 'skip_monitors');
  $server_config{base_data_path} = config_get_val($cfg, 'general', 'base_data_path',
    DEFAULT_BASE_DATA_PATH);
  $server_config{port}    = config_get_val($cfg, 'network', 'port',    DEFAULT_PORT);
  $server_config{address} = config_get_val($cfg, 'network', 'address', DEFAULT_ADDRESS);
  $server_config{event_check_interval} = config_get_val($cfg, 'customize', 'event_check_interval',
    DEFAULT_CUSTOMIZE_EVENT_CHECK_INTERVAL);
  $server_config{monitor_reload_interval} = config_get_val($cfg, 'customize', 'monitor_reload_interval',
    DEFAULT_CUSTOMIZE_MONITOR_RELOAD_INTERVAL);
  $server_config{es_rules_file} = config_get_val($cfg, 'customize', 'es_rules');
  if ($server_config{es_rules_file}) {
    main::Debug(2, "rules: Loading es rules: $server_config{es_rules_file}");
    eval { my $hr = YAML::XS::LoadFile($server_config{es_rules_file}); %es_rules = %$hr; };
    if ($@) { main::Error("rules: Failed loading es rules: $@"); }
  }

  # --- auth_config ---
  $auth_config{enabled} = config_get_val($cfg, 'auth', 'enable', DEFAULT_AUTH_ENABLE);
  $auth_config{timeout} = config_get_val($cfg, 'auth', 'timeout', DEFAULT_AUTH_TIMEOUT);

  # --- ssl_config ---
  $ssl_config{enabled}   = config_get_val($cfg, 'ssl', 'enable', DEFAULT_SSL_ENABLE);
  $ssl_config{cert_file} = config_get_val($cfg, 'ssl', 'cert');
  $ssl_config{key_file}  = config_get_val($cfg, 'ssl', 'key');

  # --- fcm_config ---
  $fcm_config{enabled} = config_get_val($cfg, 'fcm', 'enable', DEFAULT_FCM_ENABLE);
  $fcm_config{use_v1} = config_get_val($cfg, 'fcm', 'use_fcmv1', DEFAULT_USE_FCMV1);
  $fcm_config{replace_push_messages} = config_get_val($cfg, 'fcm', 'replace_push_messages',
    DEFAULT_REPLACE_PUSH_MSGS);
  $fcm_config{date_format} = config_get_val($cfg, 'fcm', 'date_format',
    DEFAULT_FCM_DATE_FORMAT);
  $fcm_config{android_priority} = config_get_val($cfg, 'fcm', 'fcm_android_priority',
    DEFAULT_FCM_ANDROID_PRIORITY);
  $fcm_config{android_ttl} = config_get_val($cfg, 'fcm', 'fcm_android_ttl');
  $fcm_config{token_file} = config_get_val($cfg, 'fcm', 'token_file',
    DEFAULT_FCM_TOKEN_FILE);
  $fcm_config{log_raw_message} = config_get_val($cfg, 'fcm', 'fcm_log_raw_message',
    DEFAULT_FCM_LOG_RAW_MESSAGE);
  $fcm_config{log_message_id} = config_get_val($cfg, 'fcm', 'fcm_log_message_id',
    DEFAULT_FCM_LOG_MESSAGE_ID);
  $fcm_config{v1_key} = config_get_val($cfg, 'fcm', 'fcm_v1_key',
    DEFAULT_FCM_V1_KEY);
  $fcm_config{v1_url} = config_get_val($cfg, 'fcm', 'fcm_v1_url',
    DEFAULT_FCM_V1_URL);
  $fcm_config{service_account_file} = config_get_val($cfg, 'fcm', 'fcm_service_account_file');
  $fcm_config{include_profile_in_push} = config_get_val($cfg, 'fcm', 'include_profile_in_push',
    DEFAULT_FCM_INCLUDE_PROFILE_IN_PUSH);

  # --- mqtt_config ---
  $mqtt_config{enabled} = config_get_val($cfg, 'mqtt', 'enable', DEFAULT_MQTT_ENABLE);
  $mqtt_config{server}       = config_get_val($cfg, 'mqtt', 'server', DEFAULT_MQTT_SERVER);
  $mqtt_config{topic}        = config_get_val($cfg, 'mqtt', 'topic',  DEFAULT_MQTT_TOPIC);
  $mqtt_config{username}     = config_get_val($cfg, 'mqtt', 'username');
  $mqtt_config{password}     = config_get_val($cfg, 'mqtt', 'password');
  $mqtt_config{tls_ca}       = config_get_val($cfg, 'mqtt', 'tls_ca');
  $mqtt_config{tls_cert}     = config_get_val($cfg, 'mqtt', 'tls_cert');
  $mqtt_config{tls_key}      = config_get_val($cfg, 'mqtt', 'tls_key');
  $mqtt_config{tls_insecure} = config_get_val($cfg, 'mqtt', 'tls_insecure');
  $mqtt_config{tick_interval} = config_get_val($cfg, 'mqtt', 'tick_interval',
    DEFAULT_MQTT_TICK_INTERVAL);
  $mqtt_config{retain} = config_get_val($cfg, 'mqtt', 'retain', DEFAULT_MQTT_RETAIN);

  # --- push_config ---
  $push_config{enabled} = config_get_val($cfg, 'push', 'use_api_push',
    DEFAULT_USE_API_PUSH);
  if ($push_config{enabled}) {
    $push_config{script} = config_get_val($cfg, 'push', 'api_push_script');
    main::Error('You have API push enabled, but no script to handle API pushes')
      if !$push_config{script};
  }

  # --- notify_config ---
  $notify_config{console_logs} = config_get_val($cfg, 'customize', 'console_logs',
    DEFAULT_CUSTOMIZE_VERBOSE) if (!$notify_config{console_logs});
  $notify_config{es_debug_level} = config_get_val($cfg, 'customize', 'es_debug_level',
    DEFAULT_CUSTOMIZE_ES_DEBUG_LEVEL);
  $notify_config{read_alarm_cause} = config_get_val($cfg, 'customize', 'read_alarm_cause',
    DEFAULT_CUSTOMIZE_READ_ALARM_CAUSE);
  $notify_config{tag_alarm_event_id} = config_get_val($cfg, 'customize', 'tag_alarm_event_id',
    DEFAULT_CUSTOMIZE_TAG_ALARM_EVENT_ID);
  $notify_config{use_custom_notification_sound} = config_get_val($cfg, 'customize',
    'use_custom_notification_sound',
    DEFAULT_CUSTOMIZE_USE_CUSTOM_NOTIFICATION_SOUND);
  $notify_config{picture_url} = config_get_val($cfg, 'customize', 'picture_url');
  $notify_config{include_picture} = config_get_val($cfg, 'customize', 'include_picture',
    DEFAULT_CUSTOMIZE_INCLUDE_PICTURE);
  $notify_config{picture_portal_username} = config_get_val($cfg, 'customize', 'picture_portal_username');
  $notify_config{picture_portal_password} = config_get_val($cfg, 'customize', 'picture_portal_password');
  $notify_config{send_event_end_notification} = config_get_val($cfg, 'customize',
    'send_event_end_notification', DEFAULT_SEND_EVENT_END_NOTIFICATION);
  $notify_config{send_event_start_notification} = config_get_val($cfg, 'customize',
    'send_event_start_notification', DEFAULT_SEND_EVENT_START_NOTIFICATION);

  # --- hooks_config ---
  $hooks_config{enabled} = config_get_val($cfg, 'customize', 'use_hooks',
    DEFAULT_USE_HOOKS);
  $hooks_config{event_start_hook} = config_get_val($cfg, 'hook', 'event_start_hook');
  $hooks_config{event_start_hook_notify_userscript} =
    config_get_val($cfg, 'hook', 'event_start_hook_notify_userscript');
  $hooks_config{event_end_hook_notify_userscript} =
    config_get_val($cfg, 'hook', 'event_end_hook_notify_userscript');

  $hooks_config{event_start_hook} = config_get_val($cfg, 'hook', 'hook_script')
    if !$hooks_config{event_start_hook};
  $hooks_config{event_end_hook} = config_get_val($cfg, 'hook', 'event_end_hook');

  $hooks_config{event_start_notify_on_hook_fail} = config_get_val($cfg, 'hook',
    'event_start_notify_on_hook_fail', DEFAULT_EVENT_START_NOTIFY_ON_HOOK_FAIL);
  $hooks_config{event_start_notify_on_hook_success} = config_get_val($cfg, 'hook',
    'event_start_notify_on_hook_success', DEFAULT_EVENT_START_NOTIFY_ON_HOOK_SUCCESS);
  $hooks_config{event_end_notify_on_hook_fail} = config_get_val($cfg, 'hook',
    'event_end_notify_on_hook_fail', DEFAULT_EVENT_END_NOTIFY_ON_HOOK_FAIL);
  $hooks_config{event_end_notify_on_hook_success} = config_get_val($cfg, 'hook',
    'event_end_notify_on_hook_success', DEFAULT_EVENT_END_NOTIFY_ON_HOOK_SUCCESS);

  $hooks_config{max_parallel_hooks} = config_get_val($cfg, 'hook', 'max_parallel_hooks',
    DEFAULT_MAX_PARALLEL_HOOKS);

  $hooks_config{event_end_notify_if_start_success} = config_get_val($cfg, 'hook',
    'event_end_notify_if_start_success', DEFAULT_EVENT_END_NOTIFY_IF_START_SUCCESS);

  $hooks_config{use_hook_description} = config_get_val($cfg, 'hook', 'use_hook_description',
    DEFAULT_HOOK_USE_HOOK_DESCRIPTION);
  $hooks_config{hook_skip_monitors} = config_get_val($cfg, 'hook', 'hook_skip_monitors');
  $hooks_config{hook_pass_image_path} = config_get_val($cfg, 'hook', 'hook_pass_image_path');
  $hooks_config{tag_detected_objects} = config_get_val($cfg, 'hook', 'tag_detected_objects',
    DEFAULT_HOOK_TAG_DETECTED_OBJECTS);
}

sub saveEsControlSettings {
  return if !$escontrol_config{enabled};
  main::Debug(2, "ESCONTROL_INTERFACE: Saving admin interfaces to $escontrol_config{file}");
  store(\%escontrol_interface_settings, $escontrol_config{file})
    or main::Fatal("Error writing to $escontrol_config{file}: $!");
}

sub loadEsControlSettings {
  if (!$escontrol_config{enabled}) {
    main::Debug(1, 'ESCONTROL_INTERFACE is disabled. Not loading control data');
    return;
  }
  main::Debug(2, "ESCONTROL_INTERFACE: Loading persistent admin interface settings from $escontrol_config{file}");
  if (!-f $escontrol_config{file}) {
    main::Debug(2, 'ESCONTROL_INTERFACE: file does not exist, creating...');
    saveEsControlSettings();
  } else {
    %escontrol_interface_settings = %{ retrieve($escontrol_config{file}) };
    my $json = encode_json(\%escontrol_interface_settings);
    main::Debug(2, "ESCONTROL_INTERFACE: Loaded parameters: $json");
  }
}

sub _yes_or_no        { return $_[0] ? 'yes' : 'no'; }
sub _value_or_undef   { return defined($_[0]) ? $_[0] : '(undefined)'; }
sub _present_or_not   { return $_[0] ? '(defined)' : '(undefined)'; }
sub _default_or_custom { return $_[0] eq $_[1] ? 'default' : 'custom'; }

sub print_config {
  my $config_file         = $main::config_file         // '(unknown)';
  my $config_file_present = $main::config_file_present  // 0;
  my $abs_config_file = File::Spec->rel2abs($config_file);

  print(
    <<"EOF"

${\(
  $config_file_present ?
  "Configuration (read $abs_config_file)" :
  "Default configuration ($abs_config_file doesn't exist)"
)}:

Secrets file.......................... ${\(_value_or_undef($secrets_filename))}
Base data path........................ ${\(_value_or_undef($server_config{base_data_path}))}
Restart interval (secs)............... ${\(_value_or_undef($server_config{restart_interval}))}

Use admin interface .................. ${\(_yes_or_no($escontrol_config{enabled}))}
Admin interface password.............. ${\(_present_or_not($escontrol_config{password}))}
Admin interface persistence file ..... ${\(_value_or_undef($escontrol_config{file}))}

Port ................................. ${\(_value_or_undef($server_config{port}))}
Address .............................. ${\(_value_or_undef($server_config{address}))}
Event check interval ................. ${\(_value_or_undef($server_config{event_check_interval}))}
Monitor reload interval .............. ${\(_value_or_undef($server_config{monitor_reload_interval}))}
Skipped monitors...................... ${\(_value_or_undef($server_config{skip_monitors}))}

Auth enabled ......................... ${\(_yes_or_no($auth_config{enabled}))}
Auth timeout ......................... ${\(_value_or_undef($auth_config{timeout}))}

Use API Push.......................... ${\(_yes_or_no($push_config{enabled}))}
API Push Script....................... ${\(_value_or_undef($push_config{script}))}

Use FCM .............................. ${\(_yes_or_no($fcm_config{enabled}))}
Use FCM V1 APIs....................... ${\(_yes_or_no($fcm_config{use_v1}))}
FCM Date Format....................... ${\(_value_or_undef($fcm_config{date_format}))}
Only show latest FCMv1 message........ ${\(_yes_or_no($fcm_config{replace_push_messages}))}
Android FCM push priority............. ${\(_value_or_undef($fcm_config{android_priority}))}
Android FCM push ttl.................. ${\(_value_or_undef($fcm_config{android_ttl}))}
Log FCM message ID.................... ${\(_value_or_undef($fcm_config{log_message_id}))}
Log RAW FCM Messages.................. ${\(_yes_or_no($fcm_config{log_raw_message}))}
FCM Service Account File.............. ${\(_value_or_undef($fcm_config{service_account_file}))}
FCM Mode.............................. ${\($fcm_config{service_account_file} ? "DIRECT (via Service Account)" : "PROXY")}
FCM V1 URL............................ ${\(_value_or_undef($fcm_config{v1_url}))}
FCM V1 Key............................ ${\(_default_or_custom($fcm_config{v1_key}, DEFAULT_FCM_V1_KEY))}

Token file ........................... ${\(_value_or_undef($fcm_config{token_file}))}

Use MQTT ............................. ${\(_yes_or_no($mqtt_config{enabled}))}
MQTT Server .......................... ${\(_value_or_undef($mqtt_config{server}))}
MQTT Topic ........................... ${\(_value_or_undef($mqtt_config{topic}))}
MQTT Username ........................ ${\(_value_or_undef($mqtt_config{username}))}
MQTT Password ........................ ${\(_present_or_not($mqtt_config{password}))}
MQTT Retain .......................... ${\(_yes_or_no($mqtt_config{retain}))}
MQTT Tick Interval ................... ${\(_value_or_undef($mqtt_config{tick_interval}))}
MQTT TLS CA .......................... ${\(_value_or_undef($mqtt_config{tls_ca}))}
MQTT TLS Cert ........................ ${\(_value_or_undef($mqtt_config{tls_cert}))}
MQTT TLS Key ......................... ${\(_value_or_undef($mqtt_config{tls_key}))}
MQTT TLS Insecure .................... ${\(_yes_or_no($mqtt_config{tls_insecure}))}

SSL enabled .......................... ${\(_yes_or_no($ssl_config{enabled}))}
SSL cert file ........................ ${\(_value_or_undef($ssl_config{cert_file}))}
SSL key file ......................... ${\(_value_or_undef($ssl_config{key_file}))}

Verbose .............................. ${\(_yes_or_no($notify_config{console_logs}))}
ES Debug level........................ ${\(_value_or_undef($notify_config{es_debug_level}))}
Read alarm cause ..................... ${\(_yes_or_no($notify_config{read_alarm_cause}))}
Tag alarm event id ................... ${\(_yes_or_no($notify_config{tag_alarm_event_id}))}
Use custom notification sound ........ ${\(_yes_or_no($notify_config{use_custom_notification_sound}))}
Send event start notification......... ${\(_yes_or_no($notify_config{send_event_start_notification}))}
Send event end notification........... ${\(_yes_or_no($notify_config{send_event_end_notification}))}
Monitor rules file.................... ${\(_value_or_undef($server_config{es_rules_file}))}

Use Hooks............................. ${\(_yes_or_no($hooks_config{enabled}))}
Max Parallel Hooks.................... ${\(_value_or_undef($hooks_config{max_parallel_hooks}))}
Hook Script on Event Start ........... ${\(_value_or_undef($hooks_config{event_start_hook}))}
User Script on Event Start............ ${\(_value_or_undef($hooks_config{event_start_hook_notify_userscript}))}
Hook Script on Event End.............. ${\(_value_or_undef($hooks_config{event_end_hook}))}
User Script on Event End.............. ${\(_value_or_undef($hooks_config{event_end_hook_notify_userscript}))}
Hook Skipped monitors................. ${\(_value_or_undef($hooks_config{hook_skip_monitors}))}

Notify on Event Start (hook success).. ${\(_value_or_undef($hooks_config{event_start_notify_on_hook_success}))}
Notify on Event Start (hook fail)..... ${\(_value_or_undef($hooks_config{event_start_notify_on_hook_fail}))}
Notify on Event End (hook success).... ${\(_value_or_undef($hooks_config{event_end_notify_on_hook_success}))}
Notify on Event End (hook fail)....... ${\(_value_or_undef($hooks_config{event_end_notify_on_hook_fail}))}
Notify End only if Start success...... ${\(_yes_or_no($hooks_config{event_end_notify_if_start_success}))}

Use Hook Description.................. ${\(_yes_or_no($hooks_config{use_hook_description}))}
Store Frame in ZM..................... ${\(_yes_or_no($hooks_config{hook_pass_image_path}))}
Tag detected objects in ZM............ ${\(_yes_or_no($hooks_config{tag_detected_objects}))}

Picture URL .......................... ${\(_value_or_undef($notify_config{picture_url}))}
Include picture....................... ${\(_yes_or_no($notify_config{include_picture}))}
Picture username ..................... ${\(_value_or_undef($notify_config{picture_portal_username}))}
Picture password ..................... ${\(_present_or_not($notify_config{picture_portal_password}))}

EOF
  );
}

1;
