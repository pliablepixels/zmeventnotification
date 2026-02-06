#!/usr/bin/env perl
# Edge case tests for undefined/missing values
# Ensures code handles incomplete data gracefully without warnings
#
# References: GitHub issues #13, #14, #15

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../";
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Warn;
use YAML::XS;
use File::Spec;
use File::Temp qw(tempfile tempdir);
use JSON;

require StubZM;

use ZmEventNotification::Config qw(:all);
use ZmEventNotification::Constants qw(:all);

# Load test config
my $fixtures = File::Spec->catdir($FindBin::Bin, 'fixtures');
my $cfg = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_es.yml'));
my $sec = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_secrets.yml'));
$ZmEventNotification::Config::secrets = $sec;
loadEsConfigSettings($cfg);

# Load rules
my $rules_data = YAML::XS::LoadFile(File::Spec->catfile($fixtures, 'test_rules.yml'));
%ZmEventNotification::Config::es_rules = %$rules_data;

#=============================================================================
# Rules.pm Edge Cases
#=============================================================================

use_ok('ZmEventNotification::Rules');
ZmEventNotification::Rules->import(':all');

subtest 'Rules.pm: undefined End hash' => sub {
    my $alarm = {
        MonitorId => 2,
        Name      => 'TestMon',
        EventId   => 100,
        Cause     => 'detected:person',
        Start     => { Cause => 'Motion' },
        # End is completely undefined - event still in progress
    };

    my ($allowed, $obj);
    warning_is {
        ($allowed, $obj) = isAllowedInRules($alarm);
    } undef, 'no warning when End hash is undefined';

    ok(defined $allowed, 'returns a result even with undefined End');
};

subtest 'Rules.pm: End defined but Cause undefined' => sub {
    my $alarm = {
        MonitorId => 2,
        Name      => 'TestMon',
        EventId   => 101,
        Cause     => 'detected:person',
        Start     => { Cause => 'Motion' },
        End       => { State => 'pending' },  # Cause key missing
    };

    my ($allowed, $obj);
    warning_is {
        ($allowed, $obj) = isAllowedInRules($alarm);
    } undef, 'no warning when End->{Cause} is undefined';

    ok(defined $allowed, 'returns a result with undefined End->{Cause}');
};

subtest 'Rules.pm: top-level Cause undefined' => sub {
    my $alarm = {
        MonitorId => 2,
        Name      => 'TestMon',
        EventId   => 102,
        Start     => { Cause => 'Motion' },
        End       => { Cause => '' },
        # Cause key missing at top level
    };

    my ($allowed, $obj);
    warning_is {
        ($allowed, $obj) = isAllowedInRules($alarm);
    } undef, 'no warning when top-level Cause is undefined';

    ok(defined $allowed, 'returns a result with undefined Cause');
};

subtest 'Rules.pm: monitor entry exists but rules key missing' => sub {
    # Temporarily add a monitor entry without rules key
    local $es_rules{notifications}{monitors}{999} = {
        # no 'rules' key
        some_other_key => 'value'
    };

    my $alarm = {
        MonitorId => 999,
        Name      => 'TestMon',
        EventId   => 103,
        Cause     => 'detected:person',
        Start     => { Cause => 'detected:person' },
    };

    my ($allowed, $obj);
    warning_is {
        ($allowed, $obj) = isAllowedInRules($alarm);
    } undef, 'no warning when rules key is missing';

    is($allowed, 1, 'allows when rules key is missing (default allow)');
};

subtest 'Rules.pm: rules key is not an array' => sub {
    # Temporarily add a monitor entry with rules as a scalar
    local $es_rules{notifications}{monitors}{998} = {
        rules => 'not_an_array'
    };

    my $alarm = {
        MonitorId => 998,
        Name      => 'TestMon',
        EventId   => 104,
        Cause     => 'detected:person',
        Start     => { Cause => 'detected:person' },
    };

    my ($allowed, $obj);
    warning_is {
        ($allowed, $obj) = isAllowedInRules($alarm);
    } undef, 'no warning when rules is not an array';

    is($allowed, 1, 'allows when rules is not an array (default allow)');
};

subtest 'Rules.pm: Start->{Cause} undefined' => sub {
    my $alarm = {
        MonitorId => 2,
        Name      => 'TestMon',
        EventId   => 105,
        Start     => { },  # Cause missing
        End       => { Cause => 'detected:person' },
        Cause     => 'detected:person',
    };

    my ($allowed, $obj);
    warning_is {
        ($allowed, $obj) = isAllowedInRules($alarm);
    } undef, 'no warning when Start->{Cause} is undefined';

    ok(defined $allowed, 'returns a result');
};

#=============================================================================
# Util.pm Edge Cases
#=============================================================================

use_ok('ZmEventNotification::Util');
ZmEventNotification::Util->import(':all');

subtest 'Util.pm getInterval: more monitors than intervals' => sub {
    my $result;
    warning_is {
        $result = getInterval('10,20', '1,2,3', 3);
    } undef, 'no warning when monitors > intervals';

    # Should return 0 (default) or undef, not crash
    ok(!$result || $result == 0, 'handles mismatched array lengths gracefully');
};

subtest 'Util.pm getInterval: empty intlist' => sub {
    my $result;
    warning_is {
        $result = getInterval('', '1,2,3', 1);
    } undef, 'no warning with empty intlist';

    # Empty intlist means monitor gets default interval of 0
    ok(!defined($result) || $result == 0, 'returns undef or 0 for empty intlist');
};

subtest 'Util.pm getInterval: empty monlist' => sub {
    my $result;
    warning_is {
        $result = getInterval('10,20', '', 1);
    } undef, 'no warning with empty monlist';

    is($result, undef, 'returns undef for empty monlist');
};

subtest 'Util.pm getInterval: undefined intlist' => sub {
    my $result;
    warning_is {
        $result = getInterval(undef, '1,2,3', 1);
    } undef, 'no warning with undefined intlist';

    # Undefined intlist means monitor gets default interval of 0
    ok(!defined($result) || $result == 0, 'returns undef or 0 for undefined intlist');
};

subtest 'Util.pm getInterval: undefined monlist' => sub {
    my $result;
    warning_is {
        $result = getInterval('10,20', undef, 1);
    } undef, 'no warning with undefined monlist';

    is($result, undef, 'returns undef for undefined monlist');
};

subtest 'Util.pm getInterval: single interval for multiple monitors' => sub {
    my $result;
    warning_is {
        $result = getInterval('10', '1,2,3', 2);
    } undef, 'no warning with single interval for multiple monitors';

    # Monitor 2 should get 0 (default) since only one interval provided
    ok(!$result || $result == 0, 'gracefully handles single interval');
};

#=============================================================================
# FCM.pm Edge Cases
#=============================================================================

# Stub out heavy deps
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

for my $pkg (qw(LWP::UserAgent HTTP::Request)) {
    (my $file = $pkg) =~ s{::}{/}g;
    $INC{"$file.pm"} = 1;
    no strict 'refs';
    *{"${pkg}::new"} = sub { bless {}, $_[0] };
    *{"${pkg}::import"} = sub { 1 };
}

use_ok('ZmEventNotification::FCM');
ZmEventNotification::FCM->import(':all');

my $tmpdir = tempdir(CLEANUP => 1);

sub _write_file {
    my ($path, $content) = @_;
    open(my $fh, '>', $path) or die "Cannot open $path: $!";
    print $fh $content;
    close($fh);
}

subtest 'FCM.pm initFCMTokens: token missing monlist key' => sub {
    my $tf = "$tmpdir/missing_monlist.txt";
    my $tokens = {
        tokens => {
            'tok_incomplete' => {
                # monlist missing
                intlist   => '0,0',
                platform  => 'android',
                pushstate => 'enabled',
            }
        }
    };
    _write_file($tf, encode_json($tokens));
    local $fcm_config{token_file} = $tf;
    @main::active_connections = ();

    warning_is {
        initFCMTokens();
    } undef, 'no warning when token missing monlist';

    is(scalar @main::active_connections, 1, 'connection created despite missing monlist');
    is($main::active_connections[0]{monlist}, '', 'monlist defaults to empty string');
};

subtest 'FCM.pm initFCMTokens: token missing all optional keys' => sub {
    my $tf = "$tmpdir/minimal_token.txt";
    my $tokens = {
        tokens => {
            'tok_minimal' => {
                # All keys missing - only token itself exists
            }
        }
    };
    _write_file($tf, encode_json($tokens));
    local $fcm_config{token_file} = $tf;
    @main::active_connections = ();

    warning_is {
        initFCMTokens();
    } undef, 'no warning when token missing all optional keys';

    is(scalar @main::active_connections, 1, 'connection created with minimal token data');
    is($main::active_connections[0]{platform}, 'unknown', 'platform defaults to unknown');
    is($main::active_connections[0]{pushstate}, 'enabled', 'pushstate defaults to enabled');
};

subtest 'FCM.pm initFCMTokens: invocations missing at key' => sub {
    my $tf = "$tmpdir/inv_no_at.txt";
    my $tokens = {
        tokens => {
            'tok_inv' => {
                monlist     => '1',
                intlist     => '0',
                platform    => 'ios',
                pushstate   => 'enabled',
                invocations => { count => 5 }  # 'at' key missing
            }
        }
    };
    _write_file($tf, encode_json($tokens));
    local $fcm_config{token_file} = $tf;
    @main::active_connections = ();

    warning_is {
        initFCMTokens();
    } undef, 'no warning when invocations missing at key';

    is(scalar @main::active_connections, 1, 'connection created');
};

subtest 'FCM.pm initFCMTokens: invocations missing count key' => sub {
    my $tf = "$tmpdir/inv_no_count.txt";
    my $tokens = {
        tokens => {
            'tok_inv2' => {
                monlist     => '1',
                intlist     => '0',
                platform    => 'ios',
                pushstate   => 'enabled',
                invocations => { at => 3 }  # 'count' key missing
            }
        }
    };
    _write_file($tf, encode_json($tokens));
    local $fcm_config{token_file} = $tf;
    @main::active_connections = ();

    warning_is {
        initFCMTokens();
    } undef, 'no warning when invocations missing count key';

    is(scalar @main::active_connections, 1, 'connection created');
};

subtest 'FCM.pm initFCMTokens: invocations is not a hash' => sub {
    my $tf = "$tmpdir/inv_not_hash.txt";
    my $tokens = {
        tokens => {
            'tok_inv3' => {
                monlist     => '1',
                intlist     => '0',
                platform    => 'ios',
                pushstate   => 'enabled',
                invocations => 'not_a_hash'  # Should be a hash
            }
        }
    };
    _write_file($tf, encode_json($tokens));
    local $fcm_config{token_file} = $tf;
    @main::active_connections = ();

    warning_is {
        initFCMTokens();
    } undef, 'no warning when invocations is not a hash';

    is(scalar @main::active_connections, 1, 'connection created');
};

#=============================================================================
# Version.pm Edge Cases
#=============================================================================

subtest 'Version.pm: VERSION is defined and valid' => sub {
    use_ok('ZmEventNotification::Version');
    ok(defined $ZmEventNotification::Version::VERSION, 'VERSION is defined');
    like($ZmEventNotification::Version::VERSION, qr/^\d+\.\d+\.\d+$/,
        'VERSION has valid format');
};

#=============================================================================
# Comprehensive warning tests - exact issue #13 scenario
#=============================================================================

subtest 'Issue #13: Rules cause fallback with missing End and Cause' => sub {
    # This is the exact scenario reported in issue #13
    my $alarm = {
        MonitorId => 2,
        Name      => 'TestMon',
        EventId   => 200,
        Start     => { Cause => 'Motion' },  # No 'detected:' - triggers fallback
        # End completely missing
        # Cause completely missing
    };

    warnings_are {
        my ($allowed, $obj) = isAllowedInRules($alarm);
    } [], 'no warnings in cause fallback (issue #13 scenario)';
};

subtest 'Issue #13: Rules with End hash but no Cause key' => sub {
    my $alarm = {
        MonitorId => 2,
        Name      => 'TestMon',
        EventId   => 201,
        Start     => { Cause => 'Motion' },
        End       => { State => 'done' },  # End exists but no Cause
    };

    warnings_are {
        my ($allowed, $obj) = isAllowedInRules($alarm);
    } [], 'no warnings with End but no Cause';
};

done_testing();
