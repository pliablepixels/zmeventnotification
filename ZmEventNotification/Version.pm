package ZmEventNotification::Version;

use strict;
use warnings;
use Exporter 'import';
use File::Basename;

our @EXPORT_OK = qw($VERSION);
our %EXPORT_TAGS = (all => \@EXPORT_OK);

# Try to read from VERSION file (development), fall back to hardcoded (installed)
our $VERSION;
BEGIN {
    # Fallback version - must be inside BEGIN block to be available at compile time
    # Updated by install.sh during installation
    my $FALLBACK_VERSION = '7.0.0';

    my $module_dir = dirname(__FILE__);
    my $version_file = "$module_dir/../VERSION";

    if (-r $version_file) {
        # Development: read from VERSION file
        if (open(my $fh, '<', $version_file)) {
            $VERSION = <$fh>;
            close $fh;
            chomp $VERSION if defined $VERSION;
            # Validate format
            $VERSION = $FALLBACK_VERSION unless $VERSION && $VERSION =~ /^\d+\.\d+\.\d+$/;
        }
    }
    $VERSION //= $FALLBACK_VERSION;
}

1;
