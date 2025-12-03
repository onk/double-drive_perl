use v5.42;
use utf8;

package DoubleDrive::Test::TempDir;

use Exporter 'import';
use File::Temp qw(tempdir);
use Path::Tiny qw(path);

our @EXPORT_OK = qw(temp_dir_with_files);

sub temp_dir_with_files (@files) {
    my $dir = tempdir(CLEANUP => 1);

    for my $file (@files) {
        if ($file =~ m{/$}) {
            # Directory (ends with /)
            path($dir, $file)->mkpath;
        } else {
            # File (creates parent directories if needed)
            path($dir, $file)->touchpath;
        }
    }

    return $dir;
}
