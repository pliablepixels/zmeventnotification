package ZmEventNotification::Util;

use strict;
use warnings;
use Exporter 'import';
use JSON;
use URI::Escape qw(uri_escape);

use ZmEventNotification::Constants qw(:all);
use ZmEventNotification::Config qw(:all);

our @EXPORT_OK = qw(
  trim rsplit uniq getInterval isValidMonIntList isInList
  getConnFields getObjectForConn getConnectionIdentity parseDetectResults
  buildPictureUrl stripFrameMatchType maskPassword appendImagePath
);

our %EXPORT_TAGS = ( all => \@EXPORT_OK );

sub trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };

sub rsplit {
  my $pattern = shift(@_);    # Precompiled regex pattern (i.e. qr/pattern/)
  my $expr    = shift(@_);    # String to split
  my $limit   = shift(@_);    # Number of chunks to split into
  map { scalar reverse($_) }
    reverse split( /$pattern/, scalar reverse($expr), $limit );
}

sub uniq {
  my %seen;
  my @array = reverse @_;    # we want the latest
  my @farray = ();
  foreach (@array) {
    next if ( $_ =~ /^\s*$/ );
    my ( $token, $monlist, $intlist, $platform, $pushstate ) =
      rsplit( qr/:/, $_, 5 );    #split (":",$_);
    next if $token eq '';
    if ( ( $pushstate ne 'enabled' ) && ( $pushstate ne 'disabled' ) ) {
      main::Debug(2, "huh? uniq read $token,$monlist,$intlist,$platform, $pushstate => forcing state to enabled");
      $pushstate = 'enabled';
    }

    if ( !$seen{$token}++ ) {
      push @farray, join(':',$token,$monlist,$intlist,$platform,$pushstate);
    }
  }
  return @farray;
}

sub getInterval {
  my $intlist = shift;
  my $monlist = shift;
  my $mid     = shift;

  $intlist //= '';
  $monlist //= '';

  my @ints = split(',', $intlist);
  my @mons = split(',', $monlist);
  my %ints;
  for my $i (0 .. $#mons) {
    $ints{$mons[$i]} = $ints[$i] // 0;
  }
  if ( defined($ints{$mid}) && $ints{$mid} ne '' ) {
    return $ints{$mid};
  }
  my ( $caller, undef, $line ) = caller;
  main::Debug(1, "interval not found for mid $mid, intlist was $intlist from $caller:$line");
  return undef;
}

sub isValidMonIntList {
  my $m = shift;
  return defined($m) && ($m ne '-1') && ($m ne '');
}

sub isInList {
  my $monlist = shift;
  my $mid     = shift;
  return 1 if ( !defined($monlist) || !$monlist || $monlist eq '-1' || $monlist eq '' );

  my %mids = map { $_ => 1 } split(',', $monlist);
  return exists $mids{$mid};
}

sub getObjectForConn {
  my $conn = shift;
  my $matched;

  foreach (@main::active_connections) {
    if ( exists $_->{conn} && $_->{conn} == $conn ) {
      $matched = $_;
      last;
    }
  }
  return $matched;
}

sub getConnFields {
  my $conn    = shift;
  my $object = getObjectForConn($conn);
  if ($object) {
    my $matched = $object->{extra_fields};
    $matched = ' [' . $matched . '] ' if $matched;
    return $matched;
  }
  return '';
}

sub getConnectionIdentity {
  my $obj = shift;

  my $identity = '';

  if ( $obj->{type} == FCM ) {
    if ( exists $obj->{conn} && $obj->{state} != INVALID_CONNECTION ) {
      $identity = $obj->{conn}->ip() . ':' . $obj->{conn}->port() . ', ';
    }
    $identity = $identity.'token ending in:...'.substr($obj->{token}, -10);
  } elsif ( $obj->{type} == WEB ) {
    if ( exists $obj->{conn} ) {
      $identity = $obj->{conn}->ip() . ':' . $obj->{conn}->port();
    } else {
      $identity = '(unknown state?)';
    }
  } elsif ( $obj->{type} == MQTT ) {
    $identity = 'MQTT ' . $mqtt_config{server};
  } else {
    $identity = 'unknown type(!)';
  }

  return $identity;
}

sub stripFrameMatchType {
  my $cause = shift;
  $cause = substr($cause, 4) if (!$hooks_config{keep_frame_match_type} && $cause =~ /^\[.\]/);
  return $cause;
}

sub buildPictureUrl {
  my ($eid, $cause, $resCode, $label) = @_;
  $label //= '';

  my $base_url = $notify_config{picture_url} // '';
  return '' if $base_url eq '';

  my $pic = $base_url =~ s/EVENTID/$eid/gr;

  if ($resCode == 1) {
    main::Debug(2, "$label: called when hook failed, not using objdetect in url");
    $pic = $pic =~ s/objdetect(_...)?/snapshot/gr;
  }

  if (!$hooks_config{event_start_hook} || !$hooks_config{enabled}) {
    main::Debug(2, "$label: no start hook or hooks disabled, not using objdetect in url");
    $pic = $pic =~ s/objdetect(_...)/snapshot/gr;
  }

  $pic .= '&username=' . $notify_config{picture_portal_username} if $notify_config{picture_portal_username};
  $pic .= '&password=' . uri_escape($notify_config{picture_portal_password}) if $notify_config{picture_portal_password};

  my $match_type = substr($cause, 0, 3);
  if ($match_type eq '[a]') {
    $pic = $pic =~ s/BESTMATCH/alarm/gr;
    main::Debug(2, "$label: Alarm frame matched, picture url: " . maskPassword($pic));
  } elsif ($match_type eq '[s]') {
    $pic = $pic =~ s/BESTMATCH/snapshot/gr;
    main::Debug(2, "$label: Snapshot frame matched, picture url: $pic");
  }

  return $pic;
}

sub maskPassword {
  my $str = shift;
  $str =~ s/pass(word)?=(.*?)($|&|})/pass$1=xxx$3/g;
  return $str;
}

sub appendImagePath {
  my ($cmd, $eid) = @_;
  my $event = new ZoneMinder::Event($eid);
  $cmd = $cmd . ' "' . $event->Path() . '"';
  main::Debug(2, 'Adding event path:' . $event->Path());
  return $cmd;
}

sub parseDetectResults {
  my $results = shift;
  $results //= '';
  my ($txt, $jsonstring) = $results ? split('--SPLIT--', $results) : ('','[]');
  $txt = '' if !$txt;
  $jsonstring = '[]' if !$jsonstring;
  main::Debug(2, "parse of hook:$txt and $jsonstring from " . ($results || '(empty)'));
  return ($txt, $jsonstring);
}

1;
