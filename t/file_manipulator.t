use v5.42;
use utf8;

use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Path::Tiny qw(path);
use lib 't/lib';
use DoubleDrive::Test::TempDir qw(temp_dir_with_files);

use lib 'lib';
use DoubleDrive::FileManipulator;
use DoubleDrive::FileListItem;

subtest 'copy_files copies files and directories' => sub {
    my $src_dir = temp_dir_with_files('file1', 'dir1/file2');
    my $dest_dir = temp_dir_with_files();

    my $failed = DoubleDrive::FileManipulator->copy_files(
        [
            DoubleDrive::FileListItem->new(path => path($src_dir, 'file1')),
            DoubleDrive::FileListItem->new(path => path($src_dir, 'dir1')),
        ],
        DoubleDrive::FileListItem->new(path => path($dest_dir)),
    );

    is $failed, [], 'no failures copying';
    ok -e path($dest_dir, 'file1'), 'file copied';
    ok -d path($dest_dir, 'dir1'), 'directory copied';
    ok -e path($dest_dir, 'dir1/file2'), 'file inside directory copied';
};

subtest 'overwrite_targets detects existing files and symlinks' => sub {
    my $src_dir = temp_dir_with_files('file1', 'file2', 'broken');
    my $dest_dir = temp_dir_with_files('file1');

    symlink 'no_target', path($dest_dir, 'broken')->stringify;    # broken link in dest

    my $existing = DoubleDrive::FileManipulator->overwrite_targets(
        [
            DoubleDrive::FileListItem->new(path => path($src_dir, 'file1')),
            DoubleDrive::FileListItem->new(path => path($src_dir, 'file2')),
            DoubleDrive::FileListItem->new(path => path($src_dir, 'broken')),
        ],
        DoubleDrive::FileListItem->new(path => path($dest_dir)),
    );

    is $existing, [ 'file1', 'broken' ], 'detects existing file and broken symlink';
};

subtest 'copy_files preserves symlinks' => sub {
    my $src_dir = temp_dir_with_files('target');
    my $dest_dir = temp_dir_with_files();

    symlink 'target', path($src_dir, 'link_to_target')->stringify;

    my $failed = DoubleDrive::FileManipulator->copy_files(
        [ DoubleDrive::FileListItem->new(path => path($src_dir, 'link_to_target')) ],
        DoubleDrive::FileListItem->new(path => path($dest_dir)),
    );

    is $failed, [], 'no failures copying symlink';
    ok -l path($dest_dir, 'link_to_target'), 'symlink copied as symlink';
    is readlink(path($dest_dir, 'link_to_target')), 'target', 'symlink target preserved';
};

subtest 'copy_files overwrites existing symlink and file with symlink' => sub {
    my $src_dir = temp_dir_with_files('target');
    my $dest_dir = temp_dir_with_files('old_target');

    symlink 'target', path($src_dir, 'link_to_target')->stringify;

    # Destination already has a symlink with a different target
    symlink 'old_target', path($dest_dir, 'link_to_target')->stringify;
    my $failed = DoubleDrive::FileManipulator->copy_files(
        [ DoubleDrive::FileListItem->new(path => path($src_dir, 'link_to_target')) ],
        DoubleDrive::FileListItem->new(path => path($dest_dir)),
    );

    is $failed, [], 'no failures overwriting existing symlink';
    ok -l path($dest_dir, 'link_to_target'), 'still a symlink after overwrite';
    is readlink(path($dest_dir, 'link_to_target')), 'target', 'symlink target replaced';

    # Destination has a regular file; should be replaced by the symlink copy
    path($dest_dir, 'link_to_target')->remove;
    path($dest_dir, 'link_to_target')->spew('old content');
    $failed = DoubleDrive::FileManipulator->copy_files(
        [ DoubleDrive::FileListItem->new(path => path($src_dir, 'link_to_target')) ],
        DoubleDrive::FileListItem->new(path => path($dest_dir)),
    );

    is $failed, [], 'no failures overwriting regular file with symlink';
    ok -l path($dest_dir, 'link_to_target'), 'file replaced by symlink';
    is readlink(path($dest_dir, 'link_to_target')), 'target', 'symlink target set after replacing file';
};

subtest 'copy_into_self detects descendant and equal destinations' => sub {
    my $dir = temp_dir_with_files('foo/sub/file1', 'bar/file2');

    my $is_inside = DoubleDrive::FileManipulator->copy_into_self(
        [ DoubleDrive::FileListItem->new(path => path($dir, 'foo')) ],
        DoubleDrive::FileListItem->new(path => path($dir, 'foo', 'sub')),
    );
    ok $is_inside, 'descendant detected';

    $is_inside = DoubleDrive::FileManipulator->copy_into_self(
        [ DoubleDrive::FileListItem->new(path => path($dir, 'foo')) ],
        DoubleDrive::FileListItem->new(path => path($dir, 'foo')),
    );
    ok $is_inside, 'equal path detected';

    $is_inside = DoubleDrive::FileManipulator->copy_into_self(
        [ DoubleDrive::FileListItem->new(path => path($dir, 'bar')) ],
        DoubleDrive::FileListItem->new(path => path($dir, 'foo')),
    );
    ok !$is_inside, 'unrelated paths allowed';

    symlink 'foo', path($dir, 'foo_link')->stringify;
    $is_inside = DoubleDrive::FileManipulator->copy_into_self(
        [ DoubleDrive::FileListItem->new(path => path($dir, 'foo_link')) ],
        DoubleDrive::FileListItem->new(path => path($dir, 'foo', 'sub')),
    );
    ok !$is_inside, 'symlink source is treated as symlink, not directory';
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
        [
            DoubleDrive::FileListItem->new(path => $file1),
            DoubleDrive::FileListItem->new(path => path($src_dir, 'file2')),
        ],
        DoubleDrive::FileListItem->new(path => path($dest_dir)),
    );

    is $failed, [ { file => 'file1', error => match qr/copy failed/ } ], 'copy failure reported';
    ok !-e path($dest_dir, 'file1'), 'failed file not copied';
    ok -e path($dest_dir, 'file2'), 'other file still copied';
};

subtest 'delete_files calls gomi with all paths and returns no failures on success' => sub {
    my $dir = temp_dir_with_files('file1', 'file2');

    my @gomi_args;
    my $mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            _run_gomi => sub ($class, @paths) { @gomi_args = @paths; return 0 },
        ],
    );

    my $failed = DoubleDrive::FileManipulator->delete_files([
        DoubleDrive::FileListItem->new(path => path($dir, 'file1')),
        DoubleDrive::FileListItem->new(path => path($dir, 'file2')),
    ]);

    is $failed, [], 'no failures on gomi success';
    is scalar(@gomi_args), 2, 'gomi called with two paths';
};

subtest 'delete_files reports all files as failed when gomi fails' => sub {
    my $dir = temp_dir_with_files('file1', 'file2');

    my $mock = mock 'DoubleDrive::FileManipulator' => (
        override => [ _run_gomi => sub { return 1 } ],
    );

    my $failed = DoubleDrive::FileManipulator->delete_files([
        DoubleDrive::FileListItem->new(path => path($dir, 'file1')),
        DoubleDrive::FileListItem->new(path => path($dir, 'file2')),
    ]);

    is scalar(@$failed), 2, 'all files reported as failed when gomi fails';
};

done_testing;
