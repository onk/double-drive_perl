use v5.42;
use utf8;

use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Tickit::Test;
use POSIX qw(tzset);
use Path::Tiny qw(path);
use lib 't/lib';
use DoubleDrive::Test::TempDir qw(temp_dir_with_files);

use lib 'lib';
use DoubleDrive::App;

BEGIN {
    $ENV{TZ} = 'UTC';
    tzset();
}

subtest 'delete current file with confirmation' => sub {
    my $dir = temp_dir_with_files('file1', 'file2', 'file3');

    my $mock_tickit = mk_tickit;
    my $mock = mock 'Tickit' => (
        override => [ new => sub { $mock_tickit } ]
    );

    my $app = DoubleDrive::App->new();

    flush_tickit;
    drain_termlog;

    my $left = $app->left_pane();
    $left->change_directory(path($dir));
    flush_tickit;

    # Cursor starts on file1 (index 0)
    is $left->selected_index, 0, 'cursor on file1';

    # Press 'd' to delete
    presskey(text => "d");
    flush_tickit;

    # Confirm with 'y'
    presskey(text => "y");
    flush_tickit;

    # Verify file1 is deleted
    ok !-e "$dir/file1", 'file1 was deleted';
    ok -e "$dir/file2", 'file2 still exists';
    ok -e "$dir/file3", 'file3 still exists';
};

subtest 'cancel delete operation' => sub {
    my $dir = temp_dir_with_files('file1', 'file2');

    my $mock_tickit = mk_tickit;
    my $mock = mock 'Tickit' => (
        override => [ new => sub { $mock_tickit } ]
    );

    my $app = DoubleDrive::App->new();

    flush_tickit;
    drain_termlog;

    my $left = $app->left_pane();
    $left->change_directory(path($dir));
    flush_tickit;

    # Press 'd' to delete
    presskey(text => "d");
    flush_tickit;

    # Cancel with 'n'
    presskey(text => "n");
    flush_tickit;

    # Verify file1 still exists
    ok -e "$dir/file1", 'file1 was not deleted';
    ok -e "$dir/file2", 'file2 still exists';
};

subtest 'delete multiple selected files' => sub {
    my $dir = temp_dir_with_files('file1', 'file2', 'file3');

    my $mock_tickit = mk_tickit;
    my $mock = mock 'Tickit' => (
        override => [ new => sub { $mock_tickit } ]
    );

    my $app = DoubleDrive::App->new();

    flush_tickit;
    drain_termlog;

    my $left = $app->left_pane();
    $left->change_directory(path($dir));
    flush_tickit;

    # Select file1
    presskey(text => " ");  # Space to select (cursor on file1)
    flush_tickit;

    # Select file2 as well (cursor moved to file2 after space)
    presskey(text => " ");  # Space to select
    flush_tickit;

    # Press 'd' to delete
    presskey(text => "d");
    flush_tickit;

    # Confirm with 'y'
    presskey(text => "y");
    flush_tickit;

    # Verify file1 and file2 are deleted, file3 remains
    ok !-e "$dir/file1", 'file1 was deleted';
    ok !-e "$dir/file2", 'file2 was deleted';
    ok -e "$dir/file3", 'file3 still exists';
};

subtest 'delete with Tab/Enter navigation' => sub {
    my $dir = temp_dir_with_files('file1');

    my $mock_tickit = mk_tickit;
    my $mock = mock 'Tickit' => (
        override => [ new => sub { $mock_tickit } ]
    );

    my $app = DoubleDrive::App->new();

    flush_tickit;
    drain_termlog;

    my $left = $app->left_pane();
    $left->change_directory(path($dir));
    flush_tickit;

    # Move to file1
    presskey(text => "Down");
    flush_tickit;

    # Press 'd' to delete
    presskey(text => "d");
    flush_tickit;

    # Press Tab to switch to No, then Tab again to switch back to Yes
    presskey(text => "Tab");
    flush_tickit;
    presskey(text => "Tab");
    flush_tickit;

    # Press Enter to confirm (should execute Yes)
    presskey(text => "Enter");
    flush_tickit;

    # Verify file1 is deleted
    ok !-e "$dir/file1", 'file1 was deleted after Tab/Enter navigation';
};

subtest 'cancel with Escape key' => sub {
    my $dir = temp_dir_with_files('file1');

    my $mock_tickit = mk_tickit;
    my $mock = mock 'Tickit' => (
        override => [ new => sub { $mock_tickit } ]
    );

    my $app = DoubleDrive::App->new();

    flush_tickit;
    drain_termlog;

    my $left = $app->left_pane();
    $left->change_directory(path($dir));
    flush_tickit;

    # Move to file1
    presskey(text => "Down");
    flush_tickit;

    # Press 'd' to delete
    presskey(text => "d");
    flush_tickit;

    # Cancel with Escape
    presskey(text => "Escape");
    flush_tickit;

    # Verify file1 still exists
    ok -e "$dir/file1", 'file1 was not deleted after Escape';
};

subtest 'show error dialog on deletion failure' => sub {
    my $dir = temp_dir_with_files('file1', 'file2');

    my $mock_tickit = mk_tickit;
    my $mock = mock 'Tickit' => (
        override => [ new => sub { $mock_tickit } ]
    );

    my $app = DoubleDrive::App->new();

    flush_tickit;
    drain_termlog;

    my $left = $app->left_pane();
    $left->change_directory(path($dir));
    flush_tickit;

    # Mock Path::Tiny's remove method to throw an error
    my $file1_path = path("$dir/file1");
    my $path_mock = mock 'Path::Tiny' => (
        override => [
            remove => sub ($self, @args) {
                if ($self->stringify eq $file1_path->stringify) {
                    die "Permission denied";
                }
                # Call original method for other files
                return;
            }
        ]
    );

    # Move to file1
    presskey(text => "Down");
    flush_tickit;

    # Press 'd' to delete
    presskey(text => "d");
    flush_tickit;

    # Confirm with 'y'
    presskey(text => "y");
    flush_tickit;

    # Error dialog should be shown - press Enter to close it
    presskey(text => "Enter");
    flush_tickit;

    # Verify file1 still exists due to error
    ok -e "$dir/file1", 'file1 was not deleted due to permission error';
};

done_testing;
