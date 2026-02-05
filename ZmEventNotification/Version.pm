package ZmEventNotification::Version;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw($VERSION);
our %EXPORT_TAGS = (all => \@EXPORT_OK);

# This version is updated by install.sh during installation.
# For development, read from VERSION file in repo root.
our $VERSION = '7.0.0';

1;
