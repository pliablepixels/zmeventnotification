#!/usr/bin/perl
#
# ==========================================================================
#
# THIS SCRIPT MUST BE RUN WITH SUDO OR STARTED VIA ZMDC.PL
#
# ZoneMinder Realtime Notification System
#
# A  light weight event notification daemon
# Uses shared memory to detect new events (polls SHM)
# Also opens a websocket connection at a configurable port
# so events can be reported
# Any client can connect to this web socket and handle it further
# for example, send it out via APNS/GCM or any other mechanism
#
# This is a much  faster and low overhead method compared to zmfilter
# as there is no DB overhead nor SQL searches for event matches

# ~ PP
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# ==========================================================================

use strict;
use warnings;

use POSIX qw(:sys_wait_h ceil);
use Time::HiRes qw/gettimeofday/;
use Time::Seconds;
use Symbol qw(qualify_to_ref);
use IO::Select;
use FindBin;
our $app_version;
BEGIN {
  require lib;
  lib->import($FindBin::RealBin);

  # Load version from module (updated by install.sh during installation)
  require ZmEventNotification::Version;
  $app_version = $ZmEventNotification::Version::VERSION;

  # Handle --version before loading heavy dependencies
  if (defined $ARGV[0] && $ARGV[0] eq '--version') {
    print("$app_version\n");
    exit(0);
  }
}
use ZmEventNotification::Constants qw(:all);
use ZmEventNotification::Config qw(:all);
use ZmEventNotification::Util qw(:all);
use ZmEventNotification::DB qw(:all);
use ZmEventNotification::MQTT qw(:all);
use ZmEventNotification::FCM qw(:all);
use ZmEventNotification::Connection qw(:all);
use ZmEventNotification::Rules qw(:all);
use ZmEventNotification::WebSocketHandler qw(:all);
use ZmEventNotification::HookProcessor qw(:all);

use ZoneMinder;
use version;

# Flush output immediately so log lines aren't buffered
$| = 1;

$ENV{PATH} = '/bin:/usr/bin';
$ENV{SHELL} = '/bin/sh' if exists $ENV{SHELL};
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};


if ( !try_use('JSON') ) {
  if ( !try_use('JSON::XS') ) {
    Fatal('JSON or JSON::XS  missing');
  }
}

# Constants (connection states, types, defaults) are in ZmEventNotification::Constants

our $es_terminate = 0;

my $child_forks = 0;    # Global tracker of active children
my $parallel_hooks = 0; # Global tracker for active hooks
my $total_forks = 0;    # Global tracker of all forks since start

my $help;

our $config_file;
our $config_file_present;
my $check_config;

my $mqtt_last_tick_time = time();

our %fcm_tokens_map;

our %monitors            = ();
my %active_events       = ();
my $monitor_reload_time = 0;
my $es_start_time       = time();
our @active_connections = ();
our $wss;
my $zmdc_active = 0;

our $is_timepiece = 1;

our $dbh = zmDbConnect(1);
logInit();
logSetSignal();

$SIG{CHLD} = 'IGNORE';
$SIG{INT} = \&shutdown_sig_handler;
$SIG{TERM} = \&shutdown_sig_handler;
$SIG{ABRT} = \&shutdown_sig_handler;
$SIG{HUP} = \&logrot;

if ( !try_use('Net::WebSocket::Server') ) {
  Fatal('Net::WebSocket::Server missing');
}

Info("Running on WebSocket library version:$Net::WebSocket::Server::VERSION");
if (version->parse($Net::WebSocket::Server::VERSION) < version->parse('0.004000')) {
  Warning("You are using an old version of Net::WebSocket::Server which can cause lockups. Please upgrade. For more information please see https://zmeventnotification.readthedocs.io/en/latest/guides/es_faq.html#the-es-randomly-hangs");
}

if ( !try_use('IO::Socket::SSL') )  { Fatal('IO::Socket::SSL missing'); }
if ( !try_use('IO::Handle') )       { Fatal('IO::Handle'); }
if ( !try_use('YAML::XS') )         { Fatal('YAML::XS missing (install libyaml-libyaml-perl)'); }
if ( !try_use('Getopt::Long') )     { Fatal('Getopt::Long missing'); }
if ( !try_use('File::Basename') )   { Fatal('File::Basename missing'); }
if ( !try_use('File::Spec') )       { Fatal('File::Spec missing'); }
if ( !try_use('URI::Escape') )      { Fatal('URI::Escape missing'); }
if ( !try_use('Storable') )         { Fatal('Storable missing'); }


if ( !try_use('Time::Piece') ) {
  Error(
    'rules: Time::Piece module missing. Dates will not work in es rules json');
  $is_timepiece = 0;
}
#
use constant USAGE => <<'USAGE';

Usage: zmeventnotification.pl [OPTION]...

  --help                              Print this page.
  --version                           Print version.
  --config=FILE                       Read options from configuration file (default: /etc/zm/zmeventnotification.yml).
                                      Any CLI options used below will override config settings.

  --check-config                      Print configuration and exit.

USAGE

GetOptions(
  'help'         => \$help,
  'config=s'     => \$config_file,
  'check-config' => \$check_config,
  'debug'        => \my $debug
);

exit( print(USAGE) ) if $help;

if ( !$config_file ) {
  $config_file         = DEFAULT_CONFIG_FILE;
  $config_file_present = -e $config_file;
} else {
  if ( !-e $config_file ) {
    Fatal("$config_file does not exist!");
  }
  $config_file_present = 1;
}

my $config;

if ($config_file_present) {
  Info("using config file: $config_file");
  eval { $config = YAML::XS::LoadFile($config_file); };
  if ($@ || !$config) {
    Fatal("Encountered errors while reading $config_file:\n$@");
  }
} else {
  $config = {};
  Info('No config file found, using inbuilt defaults');
}

$config_obj = $config;  # Store in Config.pm for use by module functions

$secrets_filename = config_get_val( $config, 'general', 'secrets' );
if ($secrets_filename) {
  Fatal("secrets file configured as $secrets_filename but does not exist")
    if ! -e $secrets_filename;
  Fatal("secrets file $secrets_filename is not readable")
    if ! -r $secrets_filename;
  Info("using secrets file: $secrets_filename");
  eval { $secrets = YAML::XS::LoadFile($secrets_filename); };
  if ($@ || !$secrets) {
    Fatal("Encountered errors while reading $secrets_filename:\n$@");
  }
}

$escontrol_config{file} =
  config_get_val( $config, 'general', 'escontrol_interface_file',
  DEFAULT_ESCONTROL_INTERFACE_FILE );
$escontrol_config{enabled} =
  config_get_val( $config, 'general', 'use_escontrol_interface',
  DEFAULT_USE_ESCONTROL_INTERFACE );
$escontrol_config{password} =
  config_get_val( $config, 'general', 'escontrol_interface_password' )
  if $escontrol_config{enabled};

loadEsControlSettings();

loadEsConfigSettings($config);

our %ssl_push_opts = ();

if ( $ssl_config{enabled} && ( !$ssl_config{cert_file} || !$ssl_config{key_file} ) ) {
  Fatal('SSL is enabled, but key or certificate file is missing');
}

our $notId = 1;

if ($hooks_config{hook_pass_image_path}) {
  if ( !try_use('ZoneMinder::Event') ) {
    Fatal(
      'ZoneMinder::Event missing, you may be using an old version. Please turn off hook_pass_image_path in your config'
    );
  }
}

sub shutdown_sig_handler {
  $es_terminate = 1;
  Debug(1, 'Received request to shutdown, please wait');
}



exit(print_config()) if $check_config;
print_config() if $debug;
if ($debug) {
  $ENV{LOG_PRINT} = 1;
  ZoneMinder::Logger::logTermLevel(DEBUG1);
}

if ($fcm_config{enabled}) {
  if ( !try_use('LWP::UserAgent')
    || !try_use('URI::URL')
    || !try_use('LWP::Protocol::https') )
  {
    Fatal(
      'FCM push mode needs LWP::Protocol::https, LWP::UserAgent and URI::URL perl packages installed'
    );
  } else {
    Info('Push enabled via FCM');
    Debug(2, "fcmv1: --> FCM V1 APIs: $fcm_config{use_v1}");
    Debug(1, "fcmv1:--> Your FCM messages will be LOGGED at pliablepixel's server because your fcm_log_raw_message in zmeventnotification.yml is yes. Please turn it off, if you don't want it to!") if $fcm_config{log_raw_message};
  }
} else {
  Info('FCM disabled.');
}

if ($push_config{enabled}) {
  Info("Pushes will be sent through APIs and will use $push_config{script}");
}

if ($mqtt_config{enabled}) {
  if (!try_use('Net::MQTT::Simple')) {
    Fatal('Net::MQTT::Simple missing');
  }
  if (defined $mqtt_config{tls_ca} && !try_use('Net::MQTT::Simple::SSL')) {
    Fatal('Net::MQTT::Simple::SSL missing');
  }
  Info('MQTT Enabled');
} else {
  Info('MQTT Disabled');
}

sub logrot {
  logReinit();
  Debug(1, 'log rotate HUP handler processed, logs re-inited');
}

sub sysreadline(*;$) {
  my ( $handle, $timeout ) = @_;
  $handle = qualify_to_ref( $handle, caller() );
  my $infinitely_patient = ( @_ == 1 || $timeout < 0 );
  my $start_time         = time();
  my $selector           = IO::Select->new();
  $selector->add($handle);
  my $line = "";
SLEEP:

  until ( at_eol($line) ) {
    unless ($infinitely_patient) {
      return $line if time() > ( $start_time + $timeout );
    }

    # sleep only 1 second before checking again
    next SLEEP unless $selector->can_read(1.0);
  INPUT_READY:
    while ( $selector->can_read(0.0) ) {
      my $was_blocking = $handle->blocking(0);
    CHAR: while ( sysread( $handle, my $nextbyte, 1 ) ) {
        $line .= $nextbyte;
        last CHAR if $nextbyte eq "\n";
      }
      $handle->blocking($was_blocking);

      # if incomplete line, keep trying
      next SLEEP unless at_eol($line);
      last INPUT_READY;
    }
  }
  return $line;
}
sub at_eol($) { $_[0] =~ /\n\z/ }

Info("|------- Starting ES version: $app_version ---------|");
Debug(2, "Started with: perl:" . $^X . " and command:" . $0);

my $zmdc_status = `zmdc.pl status zmeventnotification.pl`;
if (index($zmdc_status, 'running since') != -1) {
  $zmdc_active = 1;
  Debug(1, 'ES invoked via ZMDC. Will exit when needed and have zmdc restart it');
} else {
  Debug(1, 'ES invoked manually. Will handle restarts ourselves');
}

Warning(
  'WARNING: SSL is disabled, which means all traffic will be unencrypted')
  unless $ssl_config{enabled};

pipe( READER, WRITER ) || die "pipe failed: $!";
WRITER->autoflush(1);
my ( $rin, $rout ) = ('');
vec( $rin, fileno(READER), 1 ) = 1;
Debug(2, 'Parent<--Child pipe ready');

if ($fcm_config{enabled}) {
  my $dir = dirname($fcm_config{token_file});
  if ( !-d $dir ) {
    Debug(1, "Creating $dir to store FCM tokens");
    mkdir $dir;
  }
}

Info("Event Notification daemon v $app_version starting");
loadPredefinedConnections();
initSocketServer();
Info("Event Notification daemon exiting");
exit();

sub try_use {
  my $module = shift;
  eval("use $module");
  return ( $@ ? 0 : 1 );
}


sub checkNewEvents() {

  my @newEvents  = ();

  if ((time() - $monitor_reload_time) > $server_config{monitor_reload_interval}) {

    # use this time to keep token counters updated
    my $update_tokens = 0;
    my $tokens_data;
    if ($fcm_config{enabled}) {
      $tokens_data = readTokenFile();
      $update_tokens = 1 if $tokens_data;
    }

    # this means we have hit the reload monitor timeframe
    my $len = scalar @active_connections;
    Debug(1, 'Total event client connections: ' . $len . "\n");
    my $ndx = 1;
    foreach (@active_connections) {
      if ($update_tokens and ($_->{type} == FCM)) {
        $tokens_data->{tokens}->{$_->{token}}->{invocations}=
        defined($_->{invocations})? $_->{invocations} : {count=>0, at=>(localtime)[4]};
      }

      Debug(1, '-->checkNewEvents: Connection '
          . $ndx
          . ': ID->'
          . $_->{id} . ' IP->'
          .( exists $_->{conn} ? $_->{conn}->ip() : '(none)')
          . ' Token->:...'
          . substr( $_->{token}, -10 )
          . ' Plat:'
          . $_->{platform}
          . ' Push:'
          . $_->{pushstate});
      $ndx++;
    }

    if ($update_tokens && $fcm_config{enabled}) {
      writeTokenFile($tokens_data);
    }

    foreach my $monitor ( values(%monitors) ) {
      zmMemInvalidate($monitor);
    }
    loadMonitors();
  } # end if monitor reload time

  # loop through all monitors getting SHM state
  foreach my $monitor ( values(%monitors) ) {
    my $mid = $monitor->{Id};
    if ( !zmMemVerify($monitor) ) {
      Warning('Memory verify failed for '.$monitor->{Name}.'(id:'.$mid.')');
      loadMonitor($monitor);
      next;
    }

    my ( $state, $current_event, $trigger_cause, $trigger_text ) = zmMemRead(
      $monitor,
      [ 'shared_data:state',          'shared_data:last_event',
        'trigger_data:trigger_cause', 'trigger_data:trigger_text',
      ]
    );

    next if !$current_event;    # skip monitors that have never recorded an event

    my $alarm_cause = zmMemRead($monitor, 'shared_data:alarm_cause')
      if ($notify_config{read_alarm_cause});
    $alarm_cause = $trigger_cause
      if ( defined($trigger_cause)
      && $alarm_cause eq ''
      && $trigger_cause ne '' );

    # Alert only happens after alarm. The state before alarm
    # is STATE_PRE_ALERT. This is needed to catch alarms
    # that occur in < polling time of ES and then moves to ALERT
    if ($state == STATE_ALARM || $state == STATE_ALERT) {
      # Ensure the monitor hash exists to avoid autovivification issues
      $active_events{$mid} //= {};
      if (!$active_events{$mid}->{$current_event}) {
        if ($active_events{$mid}->{last_event_processed} and
          ($active_events{$mid}->{last_event_processed} >= $current_event)
        ) {
          Debug(2, "Discarding new event id: $current_event as last processed eid for this monitor is: "
              . $active_events{$mid}->{last_event_processed});
          next;
        }

        # this means we haven't previously worked on this alarm
        # so create an event start object for this monitor


        # First we need to close any other open events for this monitor
        foreach my $ev ( keys %{ $active_events{$mid} } ) {
          next if $ev eq 'last_event_processed';
          if (!$active_events{$mid}->{$ev}->{End}) {
            Debug(2, "Closing unclosed event:$ev of Monitor:$mid as we are in a new event");

            $active_events{$mid}->{$ev}->{End} = {
              State => 'pending',
              Time  => time(),
              Cause => getNotesFromEventDB($ev)
            };
          }
        } # end foreach active event

        # add this new event to active events
        $active_events{$mid}->{$current_event} = {
          MonitorId   => $monitor->{Id},
          MonitorName => $monitor->{Name},
          EventId     => $current_event,
          Start       => {
            State => 'pending',
            Time  => time(),
            Cause => $alarm_cause,
          },
        };

        Info("New event $current_event reported for Monitor:"
            . $monitor->{Id}
            . ' (Name:'
            . $monitor->{Name} . ') '
            . $alarm_cause
            . '[last processed eid:'
            . ($active_events{$mid}->{last_event_processed} // '')
            . ']' );

        push @newEvents,
          {
          Alarm      => $active_events{$mid}->{$current_event},
          MonitorObj => $monitor
          };
        $active_events{$mid}->{last_event_processed} = $current_event;
      } else {
 # state alarm and it is present in the active event list, so we've worked on it
        Debug(2, "We've already worked on Monitor:$mid, Event:$current_event, not doing anything more");
      }
    } # end if ( $state == STATE_ALARM || $state == STATE_ALERT )
  } # end foreach monitor

  Debug(2, 'checkEvents() new events found=' . scalar @newEvents);
  return @newEvents;
}

sub loadMonitor {
  my $monitor = shift;
  Debug(1, 'loadMonitor: re-loading monitor '.$monitor->{Name});
  zmMemInvalidate($monitor);
  if ( zmMemVerify($monitor) ) {    # This will re-init shared memory
    $monitor->{LastState} = zmGetMonitorState($monitor);
    $monitor->{LastEvent} = zmGetLastEvent($monitor);
    return 1;
  }
  return 0;                         # coming here means verify failed
}

sub loadMonitors {
  Info('Re-loading monitors');
  $monitor_reload_time = time();

  %monitors = ();
  my $sql = 'SELECT * FROM `Monitors` WHERE';
  if (version->parse(ZM_VERSION) >= version->parse('1.37.13')) {
    $sql .= ' Capturing != \'None\'';
    if (version->parse(ZM_VERSION) >= version->parse('1.37.39')) {
      $sql .= ' AND Deleted != 1';
    }
  } else {
    $sql .= ' find_in_set( `Function`, \'Modect,Mocord,Nodect\' )'
  }
  $sql .= ( $Config{ZM_SERVER_ID} ? ' AND `ServerId`=?' : '' );
  my $sth = $dbh->prepare_cached($sql)
    or Fatal("Can't prepare '$sql': " . $dbh->errstr());
  my $res = $sth->execute( $Config{ZM_SERVER_ID} ? $Config{ZM_SERVER_ID} : () )
    or Fatal("Can't execute: " . $sth->errstr());
  my %skip = map { $_ => 1 } split(',', $server_config{skip_monitors} // '');
  while ( my $monitor = $sth->fetchrow_hashref() ) {
    next if $monitor->{Deleted};
    if ( $skip{ $monitor->{Id} } ) {
      Debug(1, "$$monitor{Id} is in skip list, not going to process");
      next;
    }

    if (zmMemVerify($monitor)) {
      $monitor->{LastState}       = zmGetMonitorState($monitor);
      $monitor->{LastEvent}       = zmGetLastEvent($monitor);
      $monitors{ $monitor->{Id} } = $monitor;
    }
    Debug(1, 'Loading ' . $monitor->{Name});
  } # end while fetchrow

  populateEsControlNotification();
  saveEsControlSettings();
}

sub processJobs {
  while ( ( my $read_avail = select( $rout = $rin, undef, undef, 0.0 ) ) != 0 ) {
    if ( $read_avail < 0 ) {
      if ( !$!{EINTR} ) {
        Error("Pipe read error: $read_avail $!");
      }
    } elsif ( $read_avail > 0 ) {
      chomp( my $txt = sysreadline(READER) );
      Debug(2, "RAW TEXT-->$txt");
      my ( $job, $msg ) = split( '--TYPE--', $txt );

      if ( $job eq 'message' ) {
        my ( $id, $tmsg ) = split( '--SPLIT--', $msg );
        Debug(2, "GOT JOB==>To: $id, message: $tmsg");
        foreach (@active_connections) {
          if ( ( $_->{id} eq $id ) && exists $_->{conn} ) {
            my $tip   = $_->{conn}->ip();
            my $tport = $_->{conn}->port();
            Debug(2, "Sending child message to $tip:$tport...");
            eval { $_->{conn}->send_utf8($tmsg); };
            if ($@) {
              Debug(1, 'Marking ' . $_->{conn}->ip() . ' as bad socket');
              $_->{state} = INVALID_CONNECTION;
            }
          }
        } # end foreach active connection
      } elsif ( $job eq 'fcm_notification' ) {
        # Update badge count of active connection
        my ( $token, $badge, $count, $at ) = split( '--SPLIT--', $msg );
        Debug(2, "GOT JOB==> update badge to $badge, count to $count for: $token, at: $at");
        foreach (@active_connections) {
          if ( $_->{token} eq $token ) {
            $_->{badge} = $badge;
            $_->{invocations} = {count=>$count, at=>$at};
          }
        }
      } elsif ( $job eq 'event_description' ) {
      # hook script result will be updated in ZM DB
        my ( $mid, $eid, $desc ) = split( '--SPLIT--', $msg );
        Debug(2, 'Job: Update monitor ' . $mid . ' description:' . $desc);
        updateEventinZmDB( $eid, $desc );
      } elsif ( $job eq 'timestamp' ) {
        # marks the latest time an event was sent out. Needed for interval mgmt.
        my ( $id, $mid, $timeval ) = split( '--SPLIT--', $msg );
        Debug(2, 'Job: Update last sent timestamp of monitor:'
            . $mid . ' to '
            . $timeval
            . ' for id:'
            . $id);
        foreach (@active_connections) {
          if ( $_->{id} eq $id ) {
            $_->{last_sent}->{$mid} = $timeval;
          }
        }

      } elsif ( $job eq 'active_event_update' ) {
        my ( $mid, $eid, $type, $key, $val ) = split( '--SPLIT--', $msg );
        Debug(2, "Job: Update active_event eid:$eid, mid:$mid, type:$type, field:$key to: $val");
        if ( $key eq 'State' ) {
          $active_events{$mid}->{$eid}->{$type}->{State} = $val;
        } elsif ( $key eq 'Cause' ) {
          my ( $causeTxt, $causeJson ) = split( '--JSON--', $val );
          $active_events{$mid}->{$eid}->{$type}->{Cause} = $causeTxt;

          # if detection is not used, this may be empty
          $causeJson = '[]' if !$causeJson;
          $active_events{$mid}->{$eid}->{$type}->{DetectionJson} =
            decode_json($causeJson);
        }
      } elsif ( $job eq 'active_event_delete' ) {
        my ( $mid, $eid ) = split( '--SPLIT--', $msg );
        Debug(2, "Job: Deleting active_event eid:$eid, mid:$mid");
        delete( $active_events{$mid}->{$eid} );
        $child_forks--;
      } elsif ( $job eq 'update_parallel_hooks' ) {
        if ($msg eq 'add') {
          $parallel_hooks++;
        } elsif ($msg eq 'del') {
          $parallel_hooks--;
        } else {
          Error("Parallel hooks update: command not understood: $msg");
        }
      } elsif ( $job eq 'mqtt_publish' ) {
        my ( $id, $topic, $payload ) = split('--SPLIT--', $msg);
        Debug(2, "Job: MQTT Publish on topic: $topic");
        foreach (@active_connections) {
          if (( $_->{id} eq $id ) && exists $_->{mqtt_conn}) {
            if ($mqtt_config{retain}) {
              Debug(2, 'Job: MQTT Publish with retain');
              $_->{mqtt_conn}->retain($topic => $payload);
            } else {
              Debug(2, "Job: MQTT Publish");
              $_->{mqtt_conn}->publish( $topic => $payload );
            }
          }
        } # end foreach active connection
      } else {
        Error("Job message [$job] not recognized!");
      }
    } # end if read_avail
  } # end while select
} # end sub processJobs

sub restartES {
  $wss->shutdown();
  if ($zmdc_active) {
    Info('Exiting, zmdc will restart me');
    exit 0;
  } else {
    Debug(1, 'Self exec-ing as zmdc is not tracking me');

    Info("restarting $0");
    exec($0);
  }
}

sub initSocketServer {
  checkNewEvents();
  my $ssl_server;
  if ($ssl_config{enabled}) {
    Debug(2, 'About to start listening to socket');
    eval {
      $ssl_server = IO::Socket::SSL->new(
        Listen        => 10,
        LocalPort     => $server_config{port},
        LocalAddr     => $server_config{address},
        Proto         => 'tcp',
        Reuse         => 1,
        ReuseAddr     => 1,
        SSL_startHandshake => 0,
        SSL_cert_file => $ssl_config{cert_file},
        SSL_key_file  => $ssl_config{key_file}
      );
    };
    if ($@) {
      Error("Failed starting server: $@");
      exit(-1);
    }
    Info('Secure WS(WSS) is enabled...');
  } else {
    Info('Secure WS is disabled...');
  }
  Info('Web Socket Event Server listening on port ' . $server_config{port});

  $wss = Net::WebSocket::Server->new(
    listen => $ssl_config{enabled} ? $ssl_server : $server_config{port},
    tick_period => $server_config{event_check_interval},
    on_tick     => sub {
      if ($es_terminate) {
        Info('Event Server Terminating');
        exit(0);
      }
      my $now = time();
      my $elapsed_time_min = ceil(($now - $es_start_time)/60);
      Debug(2, "----------> Tick START (active forks:$child_forks, total forks:$total_forks, active hooks: $parallel_hooks running for:$elapsed_time_min min)<--------------");
      if ($server_config{restart_interval} && (($now - $es_start_time) > $server_config{restart_interval})) {
        Info(
          "Time to restart ES as it has been running more that $server_config{restart_interval} seconds"
        );
        restartES();
      }

      if ($mqtt_config{enabled} && (($now - $mqtt_last_tick_time) > $mqtt_config{tick_interval})) {
        Debug(2, 'MQTT tick interval (' . $mqtt_config{tick_interval} . ' sec) elapsed.');
        $mqtt_last_tick_time = $now;
        foreach (@active_connections) {
          $_->{mqtt_conn}->tick(0) if $_->{type} == MQTT;
        }
      }

      checkConnection();
      processJobs();

      Debug(2, "There are $child_forks active child forks & $parallel_hooks zm_detect processes running...");
      my @newEvents = checkNewEvents();

      Debug(2, 'There are '.scalar @newEvents.' new Events to process');

      # The child closing the db connection can affect the parent.
      zmDbDisconnect();

      foreach (@newEvents) {
        if (($parallel_hooks >= $hooks_config{max_parallel_hooks}) && ($hooks_config{max_parallel_hooks} != 0)) {
          $dbh = zmDbConnect(1);
          Error("There are $parallel_hooks hooks running as of now. This exceeds your set limit of max_parallel_hooks=$hooks_config{max_parallel_hooks}. Ignoring this event. Either increase your max_parallel_hooks value, or, adjust your ZM motion sensitivity ");
          last;
        }
        my $cpid;
        $child_forks++;
        $total_forks++;
        if ($cpid = fork() ) {
          # Parent
        } elsif (defined ($cpid)) {
          # Child
          local $SIG{'CHLD'} = 'DEFAULT';
          close(READER);
          $dbh = zmDbConnect(1);
          logTerm();
          logInit();
          logSetSignal();

          Debug(1, "Forked process:$$ to handle alarm eid:" . $_->{Alarm}->{EventId});

          # send it the list of current events to handle bcause checkNewEvents() will clean it
          processNewAlarmsInFork($_);
          Debug(1, "Ending process:$$ to handle alarms");
          logTerm();
          zmDbDisconnect();
          exit 0;
        } else {
          Fatal("Can't fork: $!");
        }
      } # for loop
      $dbh = zmDbConnect(1);
      logReinit();

      check_for_duplicate_token();
      Debug(2, "---------->Tick END (active forks:$child_forks, total forks:$total_forks, active hooks: $parallel_hooks)<--------------");
    },

    on_connect => sub {
      my ( $serv, $conn ) = @_;
      Debug(2, '---------->onConnect START<--------------');
      my ($len) = scalar @active_connections;
      Debug(1, 'got a websocket connection from '
          . $conn->ip() . ' ('
          . $len
          . ') active connections');

      $conn->on(
        utf8 => sub {
          Debug(2, '---------->onConnect msg START<--------------');
          my ( $conn, $msg ) = @_;
          my $dmsg = $msg;
          $dmsg =~ s/\"password\":\"(.*?)\"/"password":\*\*\*/;
          Debug(3, "Raw incoming message: $dmsg");
          processIncomingMessage( $conn, $msg );
          Debug(2, '---------->onConnect msg END<--------------');
        },
        handshake => sub {
          my ( $conn, $handshake ) = @_;
          Debug(2, '---------->onConnect:handshake START<--------------');
          my $fields = '';
          if ( $handshake->req->fields ) {
            my $f = $handshake->req->fields;

              $fields = $fields . ' X-Forwarded-For:' . $f->{'x-forwarded-for'}
              if $f->{'x-forwarded-for'};
          }

          my $id           = gettimeofday;
          my $connect_time = time();
          push @active_connections,
            {
            token        => '',
            type         => WEB,
            conn         => $conn,
            id           => $id,
            state        => PENDING_AUTH,
            time         => $connect_time,
            monlist      => '',
            intlist      => '',
            last_sent    => {},
            platform     => 'websocket',
            pushstate    => '',
            extra_fields => $fields,
            badge        => 0,
            category     => 'normal',
            };
          Debug(1, 'Websockets: New Connection Handshake requested from '
              . $conn->ip() . ':'
              . $conn->port()
              . getConnFields($conn)
              . ' state=pending auth, id='
              . $id);

          Debug(2, '---------->onConnect:handshake END<--------------');
        },
        disconnect => sub {
          my ( $conn, $code, $reason ) = @_;
          Debug(2, '---------->onConnect:disconnect START<--------------');
          Debug(1, 'Websocket remotely disconnected from '
              . $conn->ip()
              . getConnFields($conn));
          foreach (@active_connections) {
            if ( ( exists $_->{conn} )
              && ( $_->{conn}->ip() eq $conn->ip() )
              && ( $_->{conn}->port() eq $conn->port() ) )
            {

              # mark this for deletion only if device token
              # not present
              if ( $_->{token} eq '' ) {
                $_->{state} = PENDING_DELETE;
                Debug(1, 'Marking '
                    . $conn->ip()
                    . getConnFields($conn)
                    . " for deletion as websocket closed remotely\n");
              } else {
                Debug(1, 'Invaliding websocket, but NOT Marking '
                    . $conn->ip()
                    . getConnFields($conn)
                    . ' for deletion as token '
                    . $_->{token}
                    . " active\n");
                $_->{state} = INVALID_CONNECTION;
              }
            }
          } # end foreach active_connections
          Debug(2, '---------->onConnect:disconnect END<--------------');
        },
      );

      Debug(2, '---------->onConnect END<--------------');
    }
  );

  $wss->start();
}
