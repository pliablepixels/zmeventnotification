#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../";
use lib "$FindBin::Bin/lib";

use Test::More;

# ===== Version module tests =====

use_ok('ZmEventNotification::Version', qw($VERSION));

subtest 'version format' => sub {
    ok(defined $ZmEventNotification::Version::VERSION, 'VERSION is defined');
    like($ZmEventNotification::Version::VERSION, qr/^\d+\.\d+\.\d+$/, 'VERSION matches semver format');
};

subtest 'version export' => sub {
    can_ok('ZmEventNotification::Version', 'import');
    my @export_ok = @ZmEventNotification::Version::EXPORT_OK;
    is_deeply(\@export_ok, ['$VERSION'], 'EXPORT_OK contains $VERSION');
};

done_testing();
