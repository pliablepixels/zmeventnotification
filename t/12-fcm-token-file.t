#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../";
use lib "$FindBin::Bin/lib";

use Test::More;
use File::Temp qw(tempfile tempdir);
use JSON;

require StubZM;

use ZmEventNotification::Config qw(:all);
use ZmEventNotification::Constants qw(:all);

# Stub out heavy deps that FCM.pm imports
for my $pkg (qw(
    ZmEventNotification::MQTT
    ZmEventNotification::DB
    ZmEventNotification::WebSocketHandler
)) {
    (my $file = $pkg) =~ s{::}{/}g;
    $INC{"$file.pm"} = 1;
    no strict 'refs';
    *{"${pkg}::import"} = sub { 1 };
}

# Need LWP/HTTP stubs for FCM module compilation
for my $pkg (qw(LWP::UserAgent HTTP::Request)) {
    (my $file = $pkg) =~ s{::}{/}g;
    $INC{"$file.pm"} = 1;
    no strict 'refs';
    *{"${pkg}::new"} = sub { bless {}, $_[0] };
    *{"${pkg}::import"} = sub { 1 };
}

use_ok('ZmEventNotification::FCM');
ZmEventNotification::FCM->import(':all');

# Helpers
sub _write_file {
    my ($path, $content) = @_;
    open(my $fh, '>', $path) or die "Cannot open $path: $!";
    print $fh $content;
    close($fh);
}

sub _read_file {
    my $path = shift;
    open(my $fh, '<', $path) or die "Cannot read $path: $!";
    local $/;
    my $data = <$fh>;
    close($fh);
    return $data;
}

my $tmpdir = tempdir(CLEANUP => 1);

# ===== initFCMTokens =====

{
    # Creates file if missing
    my $tf = "$tmpdir/init_create.txt";
    local $fcm_config{token_file} = $tf;
    ok(!-f $tf, 'token file does not exist before init');
    initFCMTokens();
    ok(-f $tf, 'initFCMTokens creates file if missing');
    my $data = decode_json(_read_file($tf));
    is_deeply($data, { tokens => {} }, 'new file contains empty tokens hash');
}

{
    # Loads valid JSON, populates active_connections
    my $tf = "$tmpdir/init_load.txt";
    my $tokens = {
        tokens => {
            'tok_abc123' => {
                monlist   => '1,2',
                intlist   => '0,0',
                platform  => 'android',
                pushstate => 'enabled',
                appversion => '2.0',
                invocations => { count => 5, at => 3 }
            }
        }
    };
    _write_file($tf, encode_json($tokens));
    local $fcm_config{token_file} = $tf;
    @main::active_connections = ();
    initFCMTokens();
    is(scalar @main::active_connections, 1, 'one connection loaded');
    is($main::active_connections[0]{token}, 'tok_abc123', 'correct token');
    is($main::active_connections[0]{platform}, 'android', 'correct platform');
    is($main::active_connections[0]{type}, FCM, 'type is FCM');
    is($main::active_connections[0]{state}, INVALID_CONNECTION, 'state is INVALID_CONNECTION');
    is($main::active_connections[0]{monlist}, '1,2', 'correct monlist');
}

{
    # Migrates legacy colon-separated format to JSON
    my $tf = "$tmpdir/init_legacy.txt";
    _write_file($tf, "tok_legacy:1,2:0,0:ios:enabled\n");
    local $fcm_config{token_file} = $tf;
    @main::active_connections = ();
    initFCMTokens();
    my $data = decode_json(_read_file($tf));
    ok(exists $data->{tokens}{'tok_legacy'}, 'legacy token migrated to JSON');
    is($data->{tokens}{'tok_legacy'}{platform}, 'ios', 'platform preserved after migration');
    is(scalar @main::active_connections, 1, 'one connection after migration');
}

# ===== saveFCMTokens =====

{
    # saveFCMTokens writes new token entry
    my $tf = "$tmpdir/save_new.txt";
    _write_file($tf, '{"tokens":{}}');
    local $fcm_config{token_file} = $tf;
    local $fcm_config{enabled} = 1;
    saveFCMTokens('tok_new', '1,2', '0,0', 'android', 'enabled', undef, '3.0');
    my $data = decode_json(_read_file($tf));
    ok(exists $data->{tokens}{'tok_new'}, 'new token written');
    is($data->{tokens}{'tok_new'}{platform}, 'android', 'platform stored');
    is($data->{tokens}{'tok_new'}{appversion}, '3.0', 'appversion stored');
}

{
    # saveFCMTokens skips empty token
    my $tf = "$tmpdir/save_empty.txt";
    _write_file($tf, '{"tokens":{}}');
    local $fcm_config{token_file} = $tf;
    local $fcm_config{enabled} = 1;
    saveFCMTokens('', '1', '0', 'ios', 'enabled', undef);
    my $data = decode_json(_read_file($tf));
    is_deeply($data, { tokens => {} }, 'empty token not saved');
}

{
    # saveFCMTokens preserves existing tokens
    my $tf = "$tmpdir/save_preserve.txt";
    my $existing = { tokens => { 'tok_old' => {
        monlist => '3', intlist => '0', platform => 'ios',
        pushstate => 'enabled', invocations => { count => 1, at => 0 }
    }}};
    _write_file($tf, encode_json($existing));
    local $fcm_config{token_file} = $tf;
    local $fcm_config{enabled} = 1;
    saveFCMTokens('tok_new2', '5', '10', 'android', 'enabled', undef);
    my $data = decode_json(_read_file($tf));
    ok(exists $data->{tokens}{'tok_old'}, 'old token preserved');
    ok(exists $data->{tokens}{'tok_new2'}, 'new token added');
}

{
    # saveFCMTokens with monlist=-1 does not overwrite stored monlist
    my $tf = "$tmpdir/save_minus1.txt";
    my $existing = { tokens => { 'tok_m1' => {
        monlist => '1,2', intlist => '0,0', platform => 'android',
        pushstate => 'enabled', invocations => { count => 0, at => 0 }
    }}};
    _write_file($tf, encode_json($existing));
    local $fcm_config{token_file} = $tf;
    local $fcm_config{enabled} = 1;
    saveFCMTokens('tok_m1', '-1', '-1', 'android', 'enabled', undef);
    my $data = decode_json(_read_file($tf));
    is($data->{tokens}{'tok_m1'}{monlist}, '1,2', 'monlist=-1 did not overwrite');
    is($data->{tokens}{'tok_m1'}{intlist}, '0,0', 'intlist=-1 did not overwrite');
}

{
    # saveFCMTokens stores profile field
    my $tf = "$tmpdir/save_profile.txt";
    _write_file($tf, '{"tokens":{}}');
    local $fcm_config{token_file} = $tf;
    local $fcm_config{enabled} = 1;
    saveFCMTokens('tok_prof', '1', '0', 'android', 'enabled', undef, '3.0', 'Home Server');
    my $data = decode_json(_read_file($tf));
    is($data->{tokens}{'tok_prof'}{profile}, 'Home Server', 'profile stored in token file');
}

{
    # saveFCMTokens with no profile omits field
    my $tf = "$tmpdir/save_no_profile.txt";
    _write_file($tf, '{"tokens":{}}');
    local $fcm_config{token_file} = $tf;
    local $fcm_config{enabled} = 1;
    saveFCMTokens('tok_noprof', '1', '0', 'android', 'enabled', undef, '3.0');
    my $data = decode_json(_read_file($tf));
    ok(!exists $data->{tokens}{'tok_noprof'}{profile}, 'no profile key when not provided');
}

{
    # initFCMTokens loads profile from token data
    my $tf = "$tmpdir/init_profile.txt";
    my $tokens = {
        tokens => {
            'tok_with_profile' => {
                monlist   => '1',
                intlist   => '0',
                platform  => 'android',
                pushstate => 'enabled',
                appversion => '2.0',
                profile   => 'Office Server',
                invocations => { count => 0, at => 0 }
            }
        }
    };
    _write_file($tf, encode_json($tokens));
    local $fcm_config{token_file} = $tf;
    @main::active_connections = ();
    initFCMTokens();
    is($main::active_connections[0]{profile}, 'Office Server', 'profile loaded from token file');
}

# ===== deleteFCMToken =====

{
    # deleteFCMToken removes token from file
    my $tf = "$tmpdir/del.txt";
    my $tokens = { tokens => {
        'tok_keep' => { monlist => '1', intlist => '0', platform => 'ios', pushstate => 'enabled' },
        'tok_del'  => { monlist => '2', intlist => '0', platform => 'android', pushstate => 'enabled' },
    }};
    _write_file($tf, encode_json($tokens));
    local $fcm_config{token_file} = $tf;
    @main::active_connections = (
        { token => 'tok_del', state => VALID_CONNECTION, type => FCM },
        { token => 'tok_keep', state => VALID_CONNECTION, type => FCM },
    );
    deleteFCMToken('tok_del');
    my $data = decode_json(_read_file($tf));
    ok(!exists $data->{tokens}{'tok_del'}, 'deleted token removed from file');
    ok(exists $data->{tokens}{'tok_keep'}, 'other token preserved');
}

{
    # deleteFCMToken marks matching connection INVALID_CONNECTION
    my $tf = "$tmpdir/del_state.txt";
    _write_file($tf, '{"tokens":{"tok_inv":{}}}');
    local $fcm_config{token_file} = $tf;
    @main::active_connections = (
        { token => 'tok_inv', state => VALID_CONNECTION },
    );
    deleteFCMToken('tok_inv');
    is($main::active_connections[0]{state}, INVALID_CONNECTION, 'connection marked INVALID');
}

{
    # deleteFCMToken handles missing file gracefully
    local $fcm_config{token_file} = "$tmpdir/nonexistent_file.txt";
    @main::active_connections = ();
    # Should not die
    eval { deleteFCMToken('tok_none') };
    is($@, '', 'no error on missing file');
}

done_testing();
