use v5.42;

use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Tickit::Test;
use POSIX qw(tzset);
use Path::Tiny qw(path);
use lib 't/lib';
use DoubleDrive::Test::TempDir qw(temp_dir_with_files);

use lib 'lib';
use DoubleDrive;

BEGIN {
    $ENV{TZ} = 'UTC';
    tzset();
}

subtest 'copy current file without confirmation' => sub {
    my $src_dir = temp_dir_with_files('file1');
    my $dest_dir = temp_dir_with_files();

    my $mock_tickit = mk_tickit;
    my $mock = mock 'Tickit' => (
        override => [ new => sub { $mock_tickit } ]
    );

    my $app = DoubleDrive->new();

    flush_tickit;
    drain_termlog;

    my $left = $app->left_pane();
    my $right = $app->right_pane();

    $left->change_directory(path($src_dir)->absolute);
    $right->change_directory(path($dest_dir)->absolute);
    flush_tickit;

    # Move to file1 in left pane
    presskey(text => "Down");
    flush_tickit;

    # Press 'c' to copy (no dialog because file doesn't exist in destination)
    presskey(text => "c");
    flush_tickit;

    # Verify file1 was copied to dest_dir
    ok -e "$src_dir/file1", 'source file1 still exists';
    ok -e "$dest_dir/file1", 'file1 was copied to destination';
};

subtest 'cancel copy operation when overwriting' => sub {
    my $src_dir = temp_dir_with_files('file1');
    my $dest_dir = temp_dir_with_files('file1');  # file1 already exists

    my $mock_tickit = mk_tickit;
    my $mock = mock 'Tickit' => (
        override => [ new => sub { $mock_tickit } ]
    );

    my $app = DoubleDrive->new();

    flush_tickit;
    drain_termlog;

    my $left = $app->left_pane();
    my $right = $app->right_pane();

    $left->change_directory(path($src_dir)->absolute);
    $right->change_directory(path($dest_dir)->absolute);
    flush_tickit;

    # Write different content to dest file1
    path("$dest_dir/file1")->spew("destination content");
    my $original_content = path("$dest_dir/file1")->slurp;

    # Move to file1
    presskey(text => "Down");
    flush_tickit;

    # Press 'c' to copy (dialog shown because file exists)
    presskey(text => "c");
    flush_tickit;

    # Cancel with 'n'
    presskey(text => "n");
    flush_tickit;

    # Verify file1 was not overwritten
    my $content = path("$dest_dir/file1")->slurp;
    is $content, $original_content, 'file1 was not overwritten after cancellation';
};

subtest 'copy multiple selected files' => sub {
    my $src_dir = temp_dir_with_files('file1', 'file2', 'file3');
    my $dest_dir = temp_dir_with_files();

    my $mock_tickit = mk_tickit;
    my $mock = mock 'Tickit' => (
        override => [ new => sub { $mock_tickit } ]
    );

    my $app = DoubleDrive->new();

    flush_tickit;
    drain_termlog;

    my $left = $app->left_pane();
    my $right = $app->right_pane();

    $left->change_directory(path($src_dir)->absolute);
    $right->change_directory(path($dest_dir)->absolute);
    flush_tickit;

    # Select file1 and file2
    presskey(text => "Down");
    flush_tickit;
    presskey(text => " ");  # Space to select file1
    flush_tickit;
    presskey(text => " ");  # Space to select file2
    flush_tickit;

    # Press 'c' to copy (no dialog because files don't exist in destination)
    presskey(text => "c");
    flush_tickit;

    # Verify file1 and file2 were copied
    ok -e "$dest_dir/file1", 'file1 was copied';
    ok -e "$dest_dir/file2", 'file2 was copied';
    ok !-e "$dest_dir/file3", 'file3 was not copied';
};

subtest 'copy shows overwrite warning' => sub {
    my $src_dir = temp_dir_with_files('file1');
    my $dest_dir = temp_dir_with_files('file1');  # file1 already exists

    my $mock_tickit = mk_tickit;
    my $mock = mock 'Tickit' => (
        override => [ new => sub { $mock_tickit } ]
    );

    my $app = DoubleDrive->new();

    flush_tickit;
    drain_termlog;

    my $left = $app->left_pane();
    my $right = $app->right_pane();

    $left->change_directory(path($src_dir)->absolute);
    $right->change_directory(path($dest_dir)->absolute);
    flush_tickit;

    # Write different content to dest file1
    path("$dest_dir/file1")->spew("destination content");
    my $original_content = path("$dest_dir/file1")->slurp;

    # Move to file1
    presskey(text => "Down");
    flush_tickit;

    # Press 'c' to copy
    presskey(text => "c");
    flush_tickit;

    # Confirm overwrite with 'y'
    presskey(text => "y");
    flush_tickit;

    # Verify file was overwritten
    ok -e "$dest_dir/file1", 'file1 exists in destination';
    my $new_content = path("$dest_dir/file1")->slurp;
    isnt $new_content, $original_content, 'file1 was overwritten';
};

subtest 'copy directory recursively' => sub {
    my $src_dir = temp_dir_with_files('subdir/file1', 'subdir/file2');
    my $dest_dir = temp_dir_with_files();

    my $mock_tickit = mk_tickit;
    my $mock = mock 'Tickit' => (
        override => [ new => sub { $mock_tickit } ]
    );

    my $app = DoubleDrive->new();

    flush_tickit;
    drain_termlog;

    my $left = $app->left_pane();
    my $right = $app->right_pane();

    $left->change_directory(path($src_dir)->absolute);
    $right->change_directory(path($dest_dir)->absolute);
    flush_tickit;

    # Verify source subdir exists
    ok -d "$src_dir/subdir", 'source subdir exists before copy';

    # Move to subdir (cursor starts at ../, Down moves to first file)
    presskey(text => "Down");
    flush_tickit;

    # Press 'c' to copy (no dialog because directory doesn't exist in destination)
    presskey(text => "c");
    flush_tickit;

    # Verify directory and its contents were copied
    ok -d "$dest_dir/subdir", 'subdir was copied';
    ok -e "$dest_dir/subdir/file1", 'file1 inside subdir was copied';
    ok -e "$dest_dir/subdir/file2", 'file2 inside subdir was copied';
};

done_testing;
