use v5.42;

use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Path::Tiny qw(path);
use lib 't/lib';
use DoubleDrive::Test::TempDir qw(temp_dir_with_files);

use lib 'lib';
use DoubleDrive::FileManipulator;

subtest 'copy_files copies files and directories' => sub {
    my $src_dir = temp_dir_with_files('file1', 'dir1/file2');
    my $dest_dir = temp_dir_with_files();

    my $failed = DoubleDrive::FileManipulator->copy_files(
        [ path($src_dir, 'file1'), path($src_dir, 'dir1') ],
        path($dest_dir),
    );

    is $failed, [], 'no failures copying';
    ok -e path($dest_dir, 'file1'), 'file copied';
    ok -d path($dest_dir, 'dir1'), 'directory copied';
    ok -e path($dest_dir, 'dir1/file2'), 'file inside directory copied';
};

subtest 'copy_files reports failure and continues' => sub {
    my $src_dir = temp_dir_with_files('file1', 'file2');
    my $dest_dir = temp_dir_with_files();

    my $file1 = path($src_dir, 'file1');
    my $mock = mock 'Path::Tiny' => (
        around => [
            copy => sub ($orig, $self, @args) {
                if ($self->stringify eq $file1->stringify) {
                    die "copy failed";
                }
                return $orig->($self, @args);
            },
        ],
    );

    my $failed = DoubleDrive::FileManipulator->copy_files(
        [ $file1, path($src_dir, 'file2') ],
        path($dest_dir),
    );

    is $failed, [ { file => 'file1', error => match qr/copy failed/ } ], 'copy failure reported';
    ok !-e path($dest_dir, 'file1'), 'failed file not copied';
    ok -e path($dest_dir, 'file2'), 'other file still copied';
};

subtest 'delete_files deletes files and collects failures' => sub {
    my $dir = temp_dir_with_files('file1', 'file2');

    my $file1 = path($dir, 'file1');
    my $mock = mock 'Path::Tiny' => (
        around => [
            remove => sub ($orig, $self, @args) {
                if ($self->stringify eq $file1->stringify) {
                    die "boom";
                }
                return $orig->($self, @args);
            },
        ],
    );

    my $failed = DoubleDrive::FileManipulator->delete_files(
        [ path($dir, 'file1'), path($dir, 'file2') ],
    );

    is $failed, [ { file => 'file1', error => match qr/boom/ } ], 'failure reported';
    ok -e path($dir, 'file1'), 'file1 not removed due to failure';
    ok !-e path($dir, 'file2'), 'file2 removed successfully';
};

subtest 'delete_files reports directory removal failures and continues' => sub {
    my $dir = temp_dir_with_files('dir1/file1', 'dir2/file2');

    my $dir1 = path($dir, 'dir1');
    my $mock = mock 'Path::Tiny' => (
        around => [
            remove_tree => sub ($orig, $self, @args) {
                if ($self->stringify eq $dir1->stringify) {
                    die "remove_tree failed";
                }
                return $orig->($self, @args);
            },
        ],
    );

    my $failed = DoubleDrive::FileManipulator->delete_files(
        [ $dir1, path($dir, 'dir2') ],
    );

    is $failed, [ { file => 'dir1', error => match qr/remove_tree failed/ } ], 'remove_tree failure reported';
    ok -d $dir1, 'failed directory remains';
    ok !-d path($dir, 'dir2'), 'other directory removed';
};

done_testing;
