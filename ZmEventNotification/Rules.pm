package ZmEventNotification::Rules;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(isAllowedInRules);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

use ZmEventNotification::Constants qw(:all);
use ZmEventNotification::Config qw(:all);

use Time::Piece;
use Time::Seconds;

sub isAllowedInRules {

  my $RULE_MATCHED_RESULT     = 1;
  my $RULE_NOT_MATCHED_RESULT = 0;
  my $RULE_ERROR_RESULT       = 1;
  my $MISSING_RULE_RESULT     = 1;

  my $object_on_matched     = {};    # interesting things depending on action
  my $object_on_not_matched = {};    # interesting things depending on action

  if ( !$main::is_timepiece ) {
    main::Error('rules: Not checking rules as Time::Piece is not installed');
    return ( $RULE_ERROR_RESULT, {} );
  }
  my $alarm = shift;
  my $id    = $alarm->{MonitorId};
  my $name  = $alarm->{Name};
  my $cause = $alarm->{Start}->{Cause};

  if (index($cause, 'detected:') == -1) {
    if (index($alarm->{End}->{Cause}, 'detected:') != -1) {
      $cause = $alarm->{End}->{Cause};
    } elsif (index($alarm->{Cause}, 'detected:') != -1)  {
      $cause = $alarm->{Cause};
    }
  }

  my $eid = $alarm->{EventId};
  my $now = Time::Piece->new;

  main::Debug(2, "rules: Checking rules for alarm caused by eid:$eid, monitor:$id, at: $now with cause:$cause");

  if ( !exists( $es_rules{notifications}->{monitors} )
    || !exists( $es_rules{notifications}->{monitors}->{$id} ) )
  {
    main::Debug(1, "rules: No rules found for Monitor, allowing:$id");
    return ( $MISSING_RULE_RESULT, {} );
  }

  my $entry_ref = $es_rules{notifications}->{monitors}->{$id}->{rules};
  my $rulecnt = 0;
  foreach my $rule_ref ( @{$entry_ref} ) {
    $rulecnt++;
    main::Debug(1, "rules: (eid: $eid) -- Processing rule: $rulecnt --");

    if ( $rule_ref->{action} eq 'mute' ) {
      $RULE_MATCHED_RESULT     = 0;
      $RULE_NOT_MATCHED_RESULT = 1;
      $object_on_matched       = {};
      $object_on_not_matched   = {};
    } elsif ( $rule_ref->{action} eq 'critical_notify' ) {
      $RULE_MATCHED_RESULT     = 1;
      $RULE_NOT_MATCHED_RESULT = 1;
      $object_on_matched       = { notification_type => 'critical' };
      $object_on_not_matched   = {};
    } else {
      main::Error( "rules: unknown action:" . $rule_ref->{action} );
      return ( $RULE_ERROR_RESULT, {} );
    }

    if ( !exists( $rule_ref->{parsed_from} ) ) {
      my $from = $rule_ref->{from};
      my $to   = $rule_ref->{to};
      my $format =
        exists( $rule_ref->{time_format} )
        ? $rule_ref->{time_format}
        : "%I:%M %p";
      main::Debug(2, "rules: parsing rule $from/$to using format:$format");
      my $d_from = Time::Piece->strptime( $from, $format );
      my $d_to   = Time::Piece->strptime( $to,   $format );
      if ( $d_to < $d_from ) {
        main::Debug(2, "rules: to is less than from, so we are wrapping dates");
        $d_from -= ONE_DAY;
      }
      main::Debug(2, "rules: parsed time from: $d_from and to:$d_to");

      $rule_ref->{parsed_from} = $d_from;
      $rule_ref->{parsed_to}   = $d_to;
    }

    # Parsed entries exist use those
    my $format =
      exists( $rule_ref->{time_format} )
      ? $rule_ref->{time_format}
      : '%I:%M %p';
    my $t = Time::Piece->new->strftime($format);
    $t = Time::Piece->strptime( $t, $format );

    main::Debug(2, "rules:(eid: $eid)  seeing if now:"
        . $t
        . " is between:"
        . $rule_ref->{parsed_from} . " and "
        . $rule_ref->{parsed_to});
    if ( ($t < $rule_ref->{parsed_from}) || ($t > $rule_ref->{parsed_to}) ) {
      main::Debug(1, "rules: Skipping this rule as times don't match..");
      next;
    }

    main::Debug(2, "rules:(eid: $eid)  seeing if now:"
        . $now->wdayname
        . " is part of:"
        . $rule_ref->{daysofweek});
    if ( exists($rule_ref->{daysofweek})
      && ( index( $rule_ref->{daysofweek}, $now->wdayname ) == -1 ) )
    {
      main::Debug(1, "rules: (eid: $eid) Skipping this rule as:"
          . $t->wdayname
          . ' does not match '
          . $rule_ref->{daysofweek});
      next;
    }
    main::Debug(2, "rules:(eid: $eid)  seeing if cause_has: ->"
        . $rule_ref->{cause_has}
        . "<- is part of ->$cause<-");
    if ( exists( $rule_ref->{cause_has} ) ) {
      my $re = qr/$rule_ref->{cause_has}/i;
      if ( lc($cause) !~ /$re/) {
        main::Debug(1, "rules: (eid: $eid) Skipping this rule as "
            . $rule_ref->{cause_has}
            . " does not pattern match "
            . $cause);
        next;
      }
    }

    # coming here means this rule was matched and all conditions met
    main::Debug(1, "rules: (eid: $eid) " . $rule_ref->{action}.' rule matched');
    return ( $RULE_MATCHED_RESULT, $object_on_matched );
  } #end foreach rule_ref

  main::Debug(1, "rules: (eid: $eid) No rules matched");
  return ( $RULE_NOT_MATCHED_RESULT, $object_on_not_matched );
}

1;
