use v5.42;
use utf8;

use Test2::V0;
use Tickit::Test qw(mk_term_and_window);
use POSIX qw(tzset);
use lib 't/lib';
use DoubleDrive::Test::TempDir qw(temp_dir_with_files);
use DoubleDrive::Test::Mock qw(capture_widget_text mock_file_stat);

use lib 'lib';
use DoubleDrive::Pane;

# Note: This test uses capture_widget_text() instead of Tickit::Test's is_display()
# to focus on the FileListView content without Frame borders. This makes the test
# more focused on the Pane's text rendering logic rather than the full widget layout.

BEGIN {
    $ENV{TZ} = 'UTC';
    tzset();
}

my (undef, $test_window) = mk_term_and_window(lines => 5, cols => 24);

subtest 'initial render shows sorted files' => sub {
    my $dir = temp_dir_with_files('B', 'a');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub {}
    );
    ok @$texts, 'render called on init';

    my @lines = split /\n/, $texts->[-1];
    is $lines[0], '> a             0.0B  01/15 10:30', 'a is first';
    is $lines[1], '  B             0.0B  01/15 10:30', 'B is second';
};

subtest 'empty directory shows placeholder' => sub {
    my $dir = temp_dir_with_files();  # empty
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub {}
    );
    ok @$texts, 'render called on init for empty dir';
    is $texts->[-1], '(empty directory)', 'placeholder text rendered for empty dir';
};

subtest 'selection moves and stops at bounds' => sub {
    my $dir = temp_dir_with_files('file', 'file2');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub {}
    );

    @$texts = ();
    $pane->move_cursor(1);
    my @lines = split /\n/, $texts->[-1];
    is $lines[0], '  file          0.0B  01/15 10:30', 'first file now unselected';
    is $lines[1], '> file2         0.0B  01/15 10:30', 'second file is selected';

    $pane->move_cursor(10); # out of range
    is scalar(@$texts), 1, 'no extra render when selection would go out of bounds';
};

subtest 'change_directory to parent reselects previous directory entry' => sub {
    my $dir = temp_dir_with_files('a_dir/file', 'subdir/file');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub {}
    );

    # Move to subdir (index 1) and enter it
    $pane->move_cursor(1);
    @$texts = ();
    $pane->enter_selected();

    # Go back to parent; should select the directory we came from (subdir)
    @$texts = ();
    $pane->change_directory("..");

    my @lines = split /\n/, $texts->[-1];
    like $lines[1], qr/^> subdir\/\s+0\.0B\s+01\/15 10:30$/, 'parent view selects previous directory';
    is $pane->selected_index, 1, 'cursor on previous directory entry';
};

subtest 'enter_selected descends into directory and resets selection' => sub {
    my $dir = temp_dir_with_files('file_after', 'sub1/ignore', 'sub2/file1', 'sub2/file2');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub {}
    );
    # With directory-first sorting: sub1 is index 0, sub2 is index 1, file_after is index 2
    $pane->move_cursor(1);    # select sub2 (second directory)
    $pane->enter_selected();

    my @lines = split /\n/, $texts->[-1];
    is $lines[0], '> file1         0.0B  01/15 10:30', 'selection reset to first entry in new dir';
    is $lines[1], '  file2         0.0B  01/15 10:30', 'file2 in subdirectory';
};

subtest 'reload_directory preserves cursor position' => sub {
    my $dir = temp_dir_with_files('file1', 'file2', 'file3', 'file4');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub {}
    );

    # Move to file3 (index 2: file1, file2, file3, file4)
    $pane->move_cursor(2);
    @$texts = ();

    # Reload directory
    $pane->reload_directory();

    # Cursor should still be on file3
    my @lines = split /\n/, $texts->[-1];
    is $lines[2], '> file3         0.0B  01/15 10:30', 'cursor preserved on file3 after reload';
};

subtest 'reload_directory updates index when earlier file is deleted' => sub {
    use Path::Tiny qw(path);

    my $dir = temp_dir_with_files('file1', 'file2', 'file3', 'file4');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub {}
    );

    # State: [file1, file2, > file3, file4] (selected_index = 2)
    $pane->move_cursor(2);
    is $pane->selected_index, 2, 'cursor on file3 at index 2';

    # Delete file1
    path("$dir/file1")->remove;

    @$texts = ();
    # Reload directory
    $pane->reload_directory();

    # Expected: [file2, > file3, file4] (selected_index = 1)
    is $pane->selected_index, 1, 'cursor index updated to 1 after file1 deleted';
    my @lines = split /\n/, $texts->[-1];
    is $lines[1], '> file3         0.0B  01/15 10:30', 'cursor still on file3 at new index';
};

subtest 'reload_directory keeps similar position when cursor file is deleted' => sub {
    use Path::Tiny qw(path);

    my $dir = temp_dir_with_files('file1', 'file2', 'file3', 'file4');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub {}
    );

    # Move to file3 (index 2)
    $pane->move_cursor(2);

    # Delete file3 (the cursor file)
    path("$dir/file3")->remove;

    @$texts = ();
    # Reload directory
    $pane->reload_directory();

    # Cursor should stay at index 2 (now file4)
    is $pane->selected_index, 2, 'cursor stayed at index 2';
    my @lines = split /\n/, $texts->[-1];
    is $lines[2], '> file4         0.0B  01/15 10:30', 'cursor moved to file4 at same index';
};

done_testing;
