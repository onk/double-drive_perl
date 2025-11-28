use v5.42;
use experimental 'class';

class DoubleDrive::FileManipulator {
    use File::Copy::Recursive qw(rcopy);

    sub copy_into_self ($class, $files, $dest_path) {
        my $dest_abs = $dest_path->realpath;
        my $dest_str = $dest_abs->stringify;

        for my $file (@$files) {
            next unless $file->is_dir;
            my $src_abs = $file->realpath;
            my $src_str = $src_abs->stringify;
            next unless index($dest_str, $src_str) == 0;

            # Boundary check so /foo does not match /foobar
            my $next_char = substr($dest_str, length($src_str), 1);
            if ($next_char eq '' || $next_char eq '/') {
                return true;  # destination is inside or equal to source
            }
        }

        return false;
    }

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
