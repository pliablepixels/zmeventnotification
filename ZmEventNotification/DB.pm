package ZmEventNotification::DB;

use strict;
use warnings;
use Exporter 'import';
use version;
use POSIX qw(strftime);
use ZoneMinder;

our @EXPORT_OK = qw(getAllMonitorIds updateEventinZmDB getNotesFromEventDB getZmUserId tagEventObjects);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

our $cached_zm_user_id;
my $version_warning_logged = 0;

sub getAllMonitorIds {
  return map { $_->{Id} } values(%main::monitors);
}

sub updateEventinZmDB {
  my ( $eid, $notes ) = @_;
  $notes = $notes . ' ';
  main::Debug(1, 'updating Notes clause for Event:' . $eid . ' with:' . $notes);
  my $sql = 'UPDATE Events SET Notes=CONCAT(?,Notes) WHERE Id=?';
  my $sth = $main::dbh->prepare_cached($sql)
    or main::Fatal( "UpdateEventInZmDB: Can't prepare '$sql': " . $main::dbh->errstr() );
  my $res = $sth->execute( $notes, $eid )
    or main::Fatal( "UpdateEventInZmDB: Can't execute: " . $sth->errstr() );
  $sth->finish();
}

sub getNotesFromEventDB {
  my $eid = shift;
  my $sql = 'SELECT `Notes` from `Events` WHERE `Id`=?';
  my $sth = $main::dbh->prepare_cached($sql)
    or main::Fatal( "getNotesFromEventDB: Can't prepare '$sql': " . $main::dbh->errstr() );
  my $res = $sth->execute($eid)
    or main::Fatal( "getNotesFromEventDB: Can't execute: " . $sth->errstr() );
  my $notes = $sth->fetchrow_hashref();
  $sth->finish();

  return $notes ? $notes->{Notes} : undef;
}

sub getZmUserId {
  return $cached_zm_user_id if defined $cached_zm_user_id;

  my $secrets = $ZmEventNotification::Config::secrets;
  if (!$secrets) {
    main::Debug(1, 'tagEventObjects: No secrets file available, using uid=0');
    $cached_zm_user_id = 0;
    return 0;
  }

  my $username = $secrets->val('secrets', 'ZM_USER');
  if (!$username) {
    main::Debug(1, 'tagEventObjects: ZM_USER not found in secrets, using uid=0');
    $cached_zm_user_id = 0;
    return 0;
  }

  require ZoneMinder::User;
  my $user = ZoneMinder::User->find_one(Username => $username);
  if ($user) {
    $cached_zm_user_id = $user->{Id};
    main::Debug(1, "tagEventObjects: Resolved ZM_USER '$username' to uid=$cached_zm_user_id");
  } else {
    main::Debug(1, "tagEventObjects: Could not find ZM user '$username', using uid=0");
    $cached_zm_user_id = 0;
  }

  return $cached_zm_user_id;
}

sub tagEventObjects {
  my ($eid, $labels) = @_;

  if (version->parse(ZM_VERSION) < version->parse('1.37.44')) {
    if (!$version_warning_logged) {
      main::Warning('tagEventObjects: ZM version ' . ZM_VERSION . ' < 1.37.44, tagging not supported');
      $version_warning_logged = 1;
    }
    return;
  }

  require ZoneMinder::Tag;
  require ZoneMinder::Event_Tag;

  my $uid = getZmUserId();
  my $now = strftime('%Y-%m-%d %H:%M:%S', localtime());

  my %seen;
  for my $label (@$labels) {
    next if $seen{$label}++;

    my $tag = ZoneMinder::Tag->find_one(Name => $label);
    if ($tag) {
      main::Debug(2, "tagEventObjects: Tag '$label' exists (id=$tag->{Id}), updating LastAssignedDate");
      $tag->save({LastAssignedDate => $now});
    } else {
      main::Debug(2, "tagEventObjects: Creating new tag '$label'");
      $tag = new ZoneMinder::Tag();
      $tag->save({Name => $label, CreateDate => $now, CreatedBy => $uid, LastAssignedDate => $now});
    }

    main::Debug(2, "tagEventObjects: Linking tag '$label' (id=$tag->{Id}) to event $eid");
    # Event_Tag uses @identified_by (composite key), not $primary_key,
    # so we bless directly instead of calling new() which requires $primary_key.
    my $et = bless {}, 'ZoneMinder::Event_Tag';
    $et->save({TagId => $tag->{Id}, EventId => $eid, AssignedBy => $uid});
  }
}

1;
