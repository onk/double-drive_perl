use v5.42;
use experimental 'class';

class DoubleDrive::FileManipulator {
    use File::Copy::Recursive qw(rcopy);

    sub copy_files ($class, $files, $dest_path) {
        my $failed = [];

        for my $file (@$files) {
            try {
                my $dest_file = $dest_path->child($file->basename);
                if ($file->is_dir) {
                    rcopy($file->stringify, $dest_file->stringify)
                        or die "rcopy failed: $!";
                } else {
                    $file->copy($dest_file);
                }
            } catch ($e) {
                push @$failed, { file => $file->basename, error => $e };
            }
        }

        return $failed;
    }

    sub delete_files ($class, $files) {
        my $failed = [];

        for my $file (@$files) {
            try {
                if ($file->is_dir) {
                    $file->remove_tree;
                } else {
                    $file->remove;
                }
            } catch ($e) {
                push @$failed, { file => $file->basename, error => $e };
            }
        }

        return $failed;
    }
}
