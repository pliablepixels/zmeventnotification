package ZmEventNotification::MQTT;
use strict;
use warnings;
use Exporter 'import';
use JSON;
use ZmEventNotification::Constants qw(:all);
use ZmEventNotification::Config qw(:all);
our @EXPORT_OK   = qw(sendOverMQTTBroker initMQTT);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

sub sendOverMQTTBroker {
  my $alarm      = shift;
  my $ac         = shift;
  my $event_type = shift;
  my $resCode    = shift;

  my $description = $alarm->{Name}.':('.$alarm->{EventId}.') '.$alarm->{Cause};

  $description = 'Ended:' . $description if ( $event_type eq 'event_end' );

  my $json = encode_json(
    { monitor   => $alarm->{MonitorId},
      name      => $description,
      state     => 'alarm',
      eventid   => $alarm->{EventId},
      hookvalue => $resCode,
      eventtype => $event_type,
      detection => $alarm->{DetectionJson}
    }
  );

  main::Debug(2, 'requesting MQTT Publishing Job for EID:' . $alarm->{EventId});
  my $topic = join( '/', $mqtt_config{topic}, $alarm->{MonitorId} );

  print main::WRITER 'mqtt_publish--TYPE--'
    . $ac->{id}
    . '--SPLIT--'
    . $topic
    . '--SPLIT--'
    . $json . "\n";
}

sub initMQTT {
  my $mqtt_connection;

  if ( defined $mqtt_config{username} && defined $mqtt_config{password} ) {
    if ( defined $mqtt_config{tls_ca} ) {
      main::Info('Initializing MQTT with auth over TLS connection...');
      my $sockopts = { SSL_ca_file => $mqtt_config{tls_ca} };
      if ( defined $mqtt_config{tls_cert} && defined $mqtt_config{tls_key} ) {
        $sockopts->{SSL_cert_file} = $mqtt_config{tls_cert};
        $sockopts->{SSL_key_file}  = $mqtt_config{tls_key};
      } else {
        main::Debug(1, 'MQTT over TLS will be one way TLS as tls_cert and tls_key are not provided.');
      }
      if ( defined $mqtt_config{tls_insecure} && ($mqtt_config{tls_insecure} eq 1)) {
        $sockopts->{SSL_verify_mode} = IO::Socket::SSL::SSL_VERIFY_NONE();
      }
      $mqtt_connection = Net::MQTT::Simple::SSL->new($mqtt_config{server}, $sockopts);
    } else {
      main::Info('Initializing MQTT with auth connection...');
      $mqtt_connection = Net::MQTT::Simple->new($mqtt_config{server});
    }
    if ($mqtt_connection) {
      $ENV{MQTT_SIMPLE_ALLOW_INSECURE_LOGIN} = 'true';
      $mqtt_connection->login( $mqtt_config{username}, $mqtt_config{password} );
      main::Debug(1, 'Intialized MQTT with auth');
    } else {
      main::Error('Failed to Intialized MQTT with auth');
    }
  } else {
    main::Info('Initializing MQTT without auth connection...');
    if ($mqtt_connection = Net::MQTT::Simple->new($mqtt_config{server})) {
      main::Debug(1, 'Intialized MQTT without auth');
    } else {
      main::Error('Failed to Intialized MQTT without auth');
    }
  }

  my $id           = Time::HiRes::gettimeofday();
  push @main::active_connections,
    {
    type         => MQTT,
    state        => VALID_CONNECTION,
    time         => time(),
    monlist      => '',
    intlist      => '',
    last_sent    => {},
    extra_fields => '',
    mqtt_conn    => $mqtt_connection,
    };
}

1;
