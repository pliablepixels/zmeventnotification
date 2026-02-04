package ZmEventNotification::WebSocketHandler;
use strict;
use warnings;
use Exporter 'import';
use JSON;

use ZmEventNotification::Constants qw(:all);
use ZmEventNotification::Config qw(:all);
use ZmEventNotification::Util qw(getObjectForConn getConnFields isValidMonIntList);
use ZmEventNotification::FCM qw(saveFCMTokens);
use ZmEventNotification::DB qw(getAllMonitorIds);

our @EXPORT_OK = qw(
  processIncomingMessage validateAuth processEsControlCommand
  getNotificationStatusEsControl populateEsControlNotification
);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

sub _safe_send {
  my ($conn, $str) = @_;
  eval { $conn->send_utf8($str); };
  main::Error("Error sending message: $@") if $@;
}

sub getNotificationStatusEsControl {
  my $id = shift;
  if ( !exists $escontrol_interface_settings{notifications}{$id} ) {
    main::Error(
      "Hmm, Monitor:$id does not exist in control interface, treating it as force notify..."
    );
    return ESCONTROL_FORCE_NOTIFY;
  } else {
    return $escontrol_interface_settings{notifications}{$id};
  }
}

sub populateEsControlNotification {
  return if !$escontrol_config{enabled};
  my $found = 0;
  foreach my $monitor ( values(%main::monitors) ) {
    my $id = $monitor->{Id};
    if ( !exists $escontrol_interface_settings{notifications}{$id} ) {
      $escontrol_interface_settings{notifications}{$id} =
        ESCONTROL_DEFAULT_NOTIFY;
      $found = 1;
      main::Debug(2, "ESCONTROL_INTERFACE: Discovered new monitor:$id, settings notification to ESCONTROL_DEFAULT_NOTIFY");
    }
  }
  main::saveEsControlSettings() if $found;
}

sub processEsControlCommand {
  return if !$escontrol_config{enabled};

  my ( $json, $conn ) = @_;

  my $obj = getObjectForConn($conn);
  if ( !$obj ) {
    main::Error('ESCONTROL error matching connection to object');
    return;
  }

  if ( $obj->{category} ne 'escontrol' ) {

    my $str = encode_json(
      { event   => 'escontrol',
        type    => 'command',
        status  => 'Fail',
        reason  => 'NOTCONTROL',
      }
    );
    _safe_send($conn, $str);

    return;
  }

  if ( !$json->{data} ) {
    my $str = encode_json(
      { event  => 'escontrol',
        type   => 'command',
        status => 'Fail',
        reason => 'NODATA'
      }
    );
    _safe_send($conn, $str);

    return;
  }

  if ( $json->{data}->{command} eq 'get' ) {

    my $str = encode_json(
      { event    => 'escontrol',
        type     => '',
        status   => 'Success',
        request  => $json,
        response => encode_json( \%escontrol_interface_settings )
      }
    );
    _safe_send($conn, $str);

  } elsif ( $json->{data}->{command} eq 'mute' || $json->{data}->{command} eq 'unmute' ) {
    my $is_mute = $json->{data}->{command} eq 'mute';
    my $state = $is_mute ? ESCONTROL_FORCE_MUTE : ESCONTROL_FORCE_NOTIFY;
    my $label = $is_mute ? 'Mute' : 'Unmute';
    main::Info("ESCONTROL: Admin Interface: $label notifications");

    my @mids = $json->{data}->{monitors}
      ? @{ $json->{data}->{monitors} }
      : getAllMonitorIds();

    foreach my $mid (@mids) {
      $escontrol_interface_settings{notifications}{$mid} = $state;
      main::Debug(2, "ESCONTROL: setting notification for Mid:$mid to $state");
    }

    main::saveEsControlSettings();
    my $str = encode_json(
      { event   => 'escontrol',
        type    => '',
        status  => 'Success',
        request => $json
      }
    );
    _safe_send($conn, $str);

  } elsif ( $json->{data}->{command} eq 'edit' ) {
    my $key = $json->{data}->{key};
    my $val = $json->{data}->{val};
    main::Info("ESCONTROL_INTERFACE: Change $key to $val");
    $escontrol_interface_settings{$key} = $val;
    main::saveEsControlSettings();
    main::Info('ESCONTROL_INTERFACE: --- Doing a complete reload of config --');
    main::loadEsConfigSettings();

    my $str = encode_json(
      { event   => 'escontrol',
        type    => '',
        status  => 'Success',
        request => $json
      }
    );
    _safe_send($conn, $str);

  } elsif ( $json->{data}->{command} eq 'restart' ) {
    main::Info('ES_CONTROL: restart ES');

    my $str = encode_json(
      { event   => 'escontrol',
        type    => 'command',
        status  => 'Success',
        request => $json
      }
    );
    _safe_send($conn, $str);
    main::restartES();

  } elsif ( $json->{data}->{command} eq 'reset' ) {
    main::Info('ES_CONTROL: reset admin commands');

    my $str = encode_json(
      { event   => 'escontrol',
        type    => 'command',
        status  => 'Success',
        request => $json
      }
    );
    _safe_send($conn, $str);
    %escontrol_interface_settings = ( notifications => {} );
    populateEsControlNotification();
    main::saveEsControlSettings();
    main::Info('ESCONTROL_INTERFACE: --- Doing a complete reload of config --');
    main::loadEsConfigSettings();

  } else {
    my $str = encode_json(
      { event   => $json->{escontrol},
        type    => 'command',
        status  => 'Fail',
        reason  => 'NOTSUPPORTED',
        request => $json
      }
    );
    _safe_send($conn, $str);
  }
}

sub validateAuth {
  my ( $u, $p, $c ) = @_;

  # not an ES control auth
  if ( $c eq 'normal' ) {
    return 1 unless $auth_config{enabled};

    return 0 if ( $u eq '' || $p eq '' );
    my $sql = 'SELECT `Password` FROM `Users` WHERE `Username`=?';
    my $sth = $main::dbh->prepare_cached($sql)
      or main::Fatal( "Can't prepare '$sql': " . $main::dbh->errstr() );
    my $res = $sth->execute($u)
      or main::Fatal( "Can't execute: " . $sth->errstr() );
    my $state = $sth->fetchrow_hashref();
    $sth->finish();

    if ($state) {
      if (substr($state->{Password},0,4) eq '-ZM-') {
        main::Error("The password for $u has not been migrated in ZM. Please log into ZM with this username to migrate before using it with the ES. If that doesn't work, please configure a new user for the ES");
        return 0;
      }

      my $scheme = substr( $state->{Password}, 0, 1 );
      if ( $scheme eq '*' ) {    # mysql decode
        main::Debug(2, 'Comparing using mysql hash');
        if ( !main::try_use('Crypt::MySQL qw(password password41)') ) {
          main::Fatal('Crypt::MySQL  missing, cannot validate password');
        }
        my $encryptedPassword = password41($p);
        return $state->{Password} eq $encryptedPassword;
      } else {                     # try bcrypt
        if ( !main::try_use('Crypt::Eksblowfish::Bcrypt') ) {
          main::Fatal('Crypt::Eksblowfish::Bcrypt missing, cannot validate password');
        }
        my $saved_pass = $state->{Password};

        # perl bcrypt libs can't handle $2b$ or $2y$
        $saved_pass =~ s/^\$2.\$/\$2a\$/;
        my $new_hash = Crypt::Eksblowfish::Bcrypt::bcrypt( $p, $saved_pass );
        main::Debug(2, "Comparing using bcrypt");
        return $new_hash eq $saved_pass;
      }
    } else {
      return 0;
    }

  } else {
    # admin category
    main::Debug(1, 'Detected escontrol interface auth');
    return ( $p eq $escontrol_config{password} )
      && ($escontrol_config{enabled});
  }
}

sub processIncomingMessage {
  my ( $conn, $msg ) = @_;

  my $json_string;
  eval { $json_string = decode_json($msg); };
  if ($@) {
    main::Error("Failed decoding json in processIncomingMessage: $@");
    my $str = encode_json(
      { event  => 'malformed',
        type   => '',
        status => 'Fail',
        reason => 'BADJSON'
      }
    );
    _safe_send($conn, $str);
    return;
  }

  my $data = $json_string->{data};

  # This event type is when a command related to push notification is received
  if (( $json_string->{event} eq 'push' ) && !$fcm_config{enabled}) {
    my $str = encode_json(
      { event  => 'push',
        type   => '',
        status => 'Fail',
        reason => 'PUSHDISABLED'
      }
    );
    _safe_send($conn, $str);
    return;
  } elsif ($json_string->{event} eq 'escontrol') {
    if ( !$escontrol_config{enabled} ) {
      my $str = encode_json(
        { event  => 'escontrol',
          type   => '',
          status => 'Fail',
          reason => 'ESCONTROLDISABLED'
        }
      );
      _safe_send($conn, $str);
      return;
    }
    processEsControlCommand($json_string, $conn);
    return;
  }

#-----------------------------------------------------------------------------------
# "push" event processing
#-----------------------------------------------------------------------------------
  elsif ( ( $json_string->{event} eq 'push' ) && $fcm_config{enabled} ) {

# sets the unread event count of events for a specific connection
# the server keeps a tab of # of events it pushes out per connection
# but won't know when the client has read them, so the client call tell the server
# using this message
    if ( $data->{type} eq 'badge' ) {
      main::Debug(2, 'badge command received');
      foreach (@main::active_connections) {
        if (
          (    ( exists $_->{conn} )
            && ( $_->{conn}->ip() eq $conn->ip() )
            && ( $_->{conn}->port() eq $conn->port() )
          )
          || ( $_->{token} eq $json_string->{token} )
          )
        {
          $_->{badge} = $data->{badge};
          main::Debug(2, 'badge match reset to ' . $_->{badge});
        }
      }
      return;
    }

    # This sub type is when a device token is registered
    if ( $data->{type} eq 'token' ) {
      if (!defined($data->{token}) || ($data->{token} eq '')) {
        main::Debug(2, 'Ignoring token command, I got '.encode_json($json_string));
        return;
      }
      # a token must have a platform
      if ( !$data->{platform} ) {
        my $str = encode_json(
          { event  => 'push',
            type   => 'token',
            status => 'Fail',
            reason => 'MISSINGPLATFORM'
          }
        );
        _safe_send($conn, $str);
        return;
      }

      my $stored_invocations = undef;
      my $stored_last_sent = undef;

      foreach (@main::active_connections) {
        if ($_->{token} eq $data->{token}) {
          if (
            ( !exists $_->{conn} )
            || ( $_->{conn}->ip() ne $conn->ip()
              || $_->{conn}->port() ne $conn->port() )
            )
          {
            my $existing_token = substr( $_->{token}, -10 );
            my $new_token = substr( $data->{token}, -10 );
            my $existing_conn = $_->{conn} ? $_->{conn}->ip().':'.$_->{conn}->port() : 'undefined';
            my $new_conn = $conn ? $conn->ip().':'.$conn->port() : 'undefined';

            main::Debug(2, "JOB: new token matched existing token: ($new_token <==> $existing_token) but connection did not ($new_conn <==> $existing_conn)");
            main::Debug(1, 'JOB: Duplicate token found: marking ...' . substr( $_->{token}, -10 ) . ' to be deleted');

            $_->{state} = PENDING_DELETE;
            $stored_invocations = $_->{invocations};
            $stored_last_sent = $_->{last_sent};
          } else {
            main::Debug(2, 'JOB: token matched, updating entry in active connections');
            $_->{invocations} = $stored_invocations if defined($stored_invocations);
            $_->{last_sent} = $stored_last_sent if defined($stored_last_sent);
            $_->{type}     = FCM;
            $_->{platform} = $data->{platform};
            $_->{monlist} = $data->{monlist} if isValidMonIntList($data->{monlist});
            $_->{intlist} = $data->{intlist} if isValidMonIntList($data->{intlist});
            $_->{pushstate} = $data->{state};
            main::Debug(1, 'JOB: Storing token ...'
                . substr( $_->{token}, -10 )
                . ',monlist:'
                . $_->{monlist}
                . ',intlist:'
                . $_->{intlist}
                . ',pushstate:'
                . $_->{pushstate} . "\n");
            my ( $emonlist, $eintlist ) = saveFCMTokens(
              $_->{token},    $_->{monlist}, $_->{intlist},
              $_->{platform}, $_->{pushstate}, $_->{invocations}, $_->{appversion}
            );
            $_->{monlist} = $emonlist;
            $_->{intlist} = $eintlist;
          }
        }
        elsif ( ( exists $_->{conn} )
          && ( $_->{conn}->ip() eq $conn->ip() )
          && ( $_->{conn}->port() eq $conn->port() )
          && ( $_->{token} ne $data->{token} ) )
        {
          my $existing_token = substr( $_->{token}, -10 );
          my $new_token = substr( $data->{token}, -10 );
          my $existing_conn = $_->{conn} ? $_->{conn}->ip().':'.$_->{conn}->port() : 'undefined';
          my $new_conn = $conn ? $conn->ip().':'.$conn->port() : 'undefined';

          main::Debug(2, "JOB: connection matched ($new_conn <==> $existing_conn) but token did not ($new_token <==> $existing_token). first registration?");

          $_->{type}     = FCM;
          $_->{token}    = $data->{token};
          $_->{platform} = $data->{platform};
          $_->{monlist}  = $data->{monlist} if isValidMonIntList($data->{monlist});
          $_->{intlist}  = $data->{intlist} if isValidMonIntList($data->{intlist});
          $_->{pushstate} = $data->{state};
          $_->{invocations} = defined ($stored_invocations) ? $stored_invocations:{count=>0, at=>(localtime)[4]};
          main::Debug(1, 'JOB: Storing token ...'
              . substr( $_->{token}, -10 )
              . ',monlist:'
              . $_->{monlist}
              . ',intlist:'
              . $_->{intlist}
              . ',pushstate:'
              . $_->{pushstate} . "\n");

          my ( $emonlist, $eintlist ) = saveFCMTokens(
            $_->{token},    $_->{monlist}, $_->{intlist},
            $_->{platform}, $_->{pushstate}, $_->{invocations}, $_->{appversion}
          );
          $_->{monlist} = $emonlist;
          $_->{intlist} = $eintlist;
        }
      }
    }
  }    # event = push
  #-----------------------------------------------------------------------------------
  # "control" event processing
  #-----------------------------------------------------------------------------------
  elsif ($json_string->{event} eq 'control') {
    if ( $data->{type} eq 'filter' ) {
      if ( !exists( $data->{monlist} ) ) {
        my $str = encode_json(
          { event  => 'control',
            type   => 'filter',
            status => 'Fail',
            reason => 'MISSINGMONITORLIST'
          }
        );
        _safe_send($conn, $str);
        return;
      }
      if ( !exists( $data->{intlist} ) ) {
        my $str = encode_json(
          { event  => 'control',
            type   => 'filter',
            status => 'Fail',
            reason => 'MISSINGINTERVALLIST'
          }
        );
        _safe_send($conn, $str);
        return;
      }
      foreach (@main::active_connections) {
        if ( ( exists $_->{conn} )
          && ( $_->{conn}->ip() eq $conn->ip() )
          && ( $_->{conn}->port() eq $conn->port() ) )
        {
          $_->{monlist} = $data->{monlist};
          $_->{intlist} = $data->{intlist};
          main::Debug(2, 'Contrl: Storing token ...'
              . substr( $_->{token}, -10 )
              . ',monlist:'
              . $_->{monlist}
              . ',intlist:'
              . $_->{intlist}
              . ',pushstate:'
              . $_->{pushstate} . "\n");
          saveFCMTokens(
            $_->{token},    $_->{monlist}, $_->{intlist},
            $_->{platform}, $_->{pushstate}, $_->{invocations}, $_->{appversion}
          );
        }
      } # end foreach active_connections
    } elsif ( $data->{type} eq 'version' ) {
      foreach (@main::active_connections) {
        if ( ( exists $_->{conn} )
          && ( $_->{conn}->ip() eq $conn->ip() )
          && ( $_->{conn}->port() eq $conn->port() ) )
        {
          my $str = encode_json(
            { event   => 'control',
              type    => 'version',
              status  => 'Success',
              reason  => '',
              version => $main::app_version
            }
          );
          _safe_send($_->{conn}, $str);
        }
      } # end foreach active_connections
    } # end if daa->type
  }    # event = control

#-----------------------------------------------------------------------------------
# "auth" event processing
#-----------------------------------------------------------------------------------
# This event type is when a command related to authorization is sent
  elsif ( $json_string->{event} eq 'auth' ) {
    my $uname      = $data->{user};
    my $pwd        = $data->{password};
    my $appversion = $data->{appversion};
    my $category   = exists($json_string->{category}) ? $json_string->{category} : 'normal';

    if ( $category ne 'normal' && $category ne 'escontrol' ) {
      main::Debug(1, "Auth category $category is invalid. Resetting it to 'normal'");
      $category = 'normal';
    }

    my $monlist = exists($data->{monlist}) ? $data->{monlist} : '';
    my $intlist = exists($data->{intlist}) ? $data->{intlist} : '';

    foreach (@main::active_connections) {
      if ( ( exists $_->{conn} )
        && ( $_->{conn}->ip() eq $conn->ip() )
        && ( $_->{conn}->port() eq $conn->port() ) )

        # && ( $_->{state} == PENDING_AUTH ) ) # lets allow multiple auths
      {
        if ( !validateAuth( $uname, $pwd, $category ) ) {
          # bad username or password, so reject and mark for deletion
          my $str = encode_json(
            { event  => 'auth',
              type   => '',
              status => 'Fail',
              reason => (( $category eq 'escontrol' && !$escontrol_config{enabled} ) ? 'ESCONTROLDISABLED' : 'BADAUTH')
            }
          );
          _safe_send($_->{conn}, $str);
          main::Debug(1, 'marking for deletion - bad authentication provided by '.$_->{conn}->ip());
          $_->{state} = PENDING_DELETE;
        } else {

          # all good, connection auth was valid
          $_->{category}   = $category;
          $_->{appversion} = $appversion;
          $_->{state}      = VALID_CONNECTION;
          $_->{monlist}    = $monlist;
          $_->{intlist}    = $intlist;
          $_->{token}      = '';
          my $str = encode_json(
            { event   => 'auth',
              type    => '',
              status  => 'Success',
              reason  => '',
              version => $main::app_version
            }
          );
          _safe_send($_->{conn}, $str);
          main::Info( "Correct authentication provided by " . $_->{conn}->ip() );
        } # end if validateAuth
      } # end if this is the right connection
    } # end foreach active connection
  }    # event = auth
  else {
    my $str = encode_json(
      { event  => $json_string->{event},
        type   => '',
        status => 'Fail',
        reason => 'NOTSUPPORTED'
      }
    );
    _safe_send($conn, $str);
  }
}

1;
