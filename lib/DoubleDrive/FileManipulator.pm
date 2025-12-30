use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::FileManipulator {
    use File::Copy::Recursive qw(rcopy rmove);

    sub overwrite_targets ($class, $file_items, $dest_item) {
        my $existing = [];
        my $dest_path = $dest_item->path;

        for my $item (@$file_items) {
            my $file = $item->path;
            my $dest_file = $dest_path->child($file->basename);
            my $dest_str = $dest_file->stringify;

            # -e misses broken symlinks; include -l to catch them
            push @$existing, $item->basename if (-e $dest_str || -l $dest_str);
        }

        return $existing;
    }

    sub copy_into_self ($class, $file_items, $dest_item) {
        my $dest_path = $dest_item->path;
        my $dest_abs = $dest_path->realpath;
        my $dest_str = $dest_abs->stringify;

        for my $item (@$file_items) {
            my $file = $item->path;
            my $file_str = $file->stringify;
            next if -l $file_str;    # treat symlinks as files, not directories
            next unless $file->is_dir;
            my $src_abs = $file->realpath;
            my $src_str = $src_abs->stringify;
            next unless index($dest_str, $src_str) == 0;

            # Boundary check so /foo does not match /foobar
            my $next_char = substr($dest_str, length($src_str), 1);
            if ($next_char eq '' || $next_char eq '/') {
                return true;    # destination is inside or equal to source
            }
        }

        return false;
    }

    sub copy_files ($class, $file_items, $dest_item) {
        my $failed = [];
        my $dest_path = $dest_item->path;

        for my $item (@$file_items) {
            my $file = $item->path;
            try {
                my $dest_file = $dest_path->child($file->basename);
                my $file_str = $file->stringify;
                my $dest_str = $dest_file->stringify;

                if (-l $file_str) {
                    my $target = readlink $file_str;
                    die "readlink failed: $!" unless defined $target;

                    # Replace existing non-directory destinations when overwriting symlinks
                    if (-l $dest_str || (-e $dest_str && !-d $dest_str)) {
                        $dest_file->remove;
                    }

                    symlink $target, $dest_str
                        or die "symlink failed: $!";
                } elsif ($file->is_dir) {
                    rcopy($file->stringify, $dest_file->stringify)
                        or die "rcopy failed: $!";
                } else {
                    $file->copy($dest_file);
                }
            } catch ($e) {
                push @$failed, { file => $item->basename, error => $e };
            }
        }

        return $failed;
    }

    sub move_files ($class, $file_items, $dest_item) {
        my $failed = [];
        my $dest_path = $dest_item->path;

        for my $item (@$file_items) {
            my $file = $item->path;
            try {
                my $dest_file = $dest_path->child($file->basename);

                if ($file->is_dir) {
                    rmove($file->stringify, $dest_file->stringify)
                        or die "rmove failed: $!";
                } else {
                    $file->move($dest_file);
                }
            } catch ($e) {
                push @$failed, { file => $item->basename, error => $e };
            }
        }

        return $failed;
    }

    sub delete_files ($class, $file_items) {
        my $failed = [];

        for my $item (@$file_items) {
            my $file = $item->path;
            try {
                if (-l $file->stringify) {
                    $file->remove;
                } elsif ($file->is_dir) {
                    $file->remove_tree;
                } else {
                    $file->remove;
                }
            } catch ($e) {
                push @$failed, { file => $item->basename, error => $e };
            }
        }

        return $failed;
    }
}
