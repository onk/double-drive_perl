use v5.42;

use Test2::V0;
use Tickit::Test qw(mk_term_and_window);
use POSIX qw(tzset);
use lib 't/lib';
use DoubleDrive::Test::TempDir qw(temp_dir_with_files);
use DoubleDrive::Test::Mock qw(capture_widget_text mock_file_stat);

use lib 'lib';
use DoubleDrive::Pane;

BEGIN {
    $ENV{TZ} = 'UTC';
    tzset();
}

my (undef, $test_window) = mk_term_and_window(lines => 5, cols => 24);

subtest 'toggle_selection marks file and moves cursor down' => sub {
    my $dir = temp_dir_with_files('file1', 'file2', 'file3');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub {}
    );

    # Move to first file and toggle selection
    $pane->move_selection(1);
    @$texts = ();
    $pane->toggle_selection();

    my @lines = split /\n/, $texts->[-1];
    is $lines[0], '  ../           0.0B  01/15 10:30', 'parent not selected';
    is $lines[1], ' *file1         0.0B  01/15 10:30', 'file1 selected, cursor moved';
    is $lines[2], '> file2         0.0B  01/15 10:30', 'cursor on file2';
};

subtest 'toggle_selection on cursor shows >* indicator' => sub {
    my $dir = temp_dir_with_files('file1', 'file2');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub {}
    );

    # Move to first file
    $pane->move_selection(1);
    $pane->toggle_selection();

    # Move back to selected file
    @$texts = ();
    $pane->move_selection(-1);

    my @lines = split /\n/, $texts->[-1];
    is $lines[1], '>*file1         0.0B  01/15 10:30', 'file1 shows >* when selected and cursor';
};

subtest 'toggle_selection twice deselects file' => sub {
    my $dir = temp_dir_with_files('file1', 'file2');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub {}
    );

    # Select and deselect on same file
    $pane->move_selection(1);
    $pane->toggle_selection(); # selects file1, moves to file2
    @$texts = ();
    # Move back to file1 and toggle again to deselect
    $pane->move_selection(-1);
    $pane->toggle_selection(); # deselects file1, moves to file2

    my @lines = split /\n/, $texts->[-1];
    is $lines[1], '  file1         0.0B  01/15 10:30', 'file1 deselected';
    is $lines[2], '> file2         0.0B  01/15 10:30', 'cursor moved to file2';
};

subtest 'get_files_to_operate returns selected files in file list order' => sub {
    my $dir = temp_dir_with_files('file1', 'file2', 'file3');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub {}
    );

    # Select file1 and file2 (list order: ../, file1, file2, file3)
    $pane->move_selection(1);      # cursor on file1
    $pane->toggle_selection();     # selects file1, moves to file2
    $pane->toggle_selection();     # selects file2, moves to file3

    my $files = $pane->get_files_to_operate();
    is scalar(@$files), 2, 'returns 2 selected files';
    is $files->[0]->basename, 'file1', 'first file is file1 (file list order)';
    is $files->[1]->basename, 'file2', 'second file is file2 (file list order)';
};

subtest 'get_files_to_operate returns current file when none selected' => sub {
    my $dir = temp_dir_with_files('file1', 'file2');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub {}
    );

    $pane->move_selection(1);
    my $files = $pane->get_files_to_operate();

    is scalar(@$files), 1, 'returns 1 file';
    is $files->[0]->basename, 'file1', 'returns current file under cursor';
};

subtest 'selection cleared when changing directory' => sub {
    my $dir = temp_dir_with_files('subdir/file1', 'file2');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub {}
    );

    # Select file2 (index 0: ../, 1: subdir/, 2: file2)
    $pane->move_selection(2);
    $pane->toggle_selection();

    # Verify file2 is in selected files before dir change
    my $files_before = $pane->get_files_to_operate();
    is scalar(@$files_before), 1, 'file2 is selected';

    # Move to and enter subdirectory
    $pane->move_selection(-1); # Move to subdir (index 1)
    $pane->enter_selected();

    # After entering subdir, selections should be cleared
    # (subdir contains: ../ at 0, file1 at 1)
    my $files = $pane->get_files_to_operate();
    is scalar(@$files), 1, 'only one file returned (no selections, just current file)';
    # Verify selection was actually cleared by checking we only get current file
    isnt $files->[0]->basename, 'file2', 'file2 is no longer selected (selection was cleared)';
};

subtest 'status text shows selection count' => sub {
    my $dir = temp_dir_with_files('file1', 'file2', 'file3');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $status_text;
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub ($text) { $status_text = $text }
    );

    $pane->set_active(true);
    $pane->move_selection(1);  # Move to file1
    is $status_text, '[2/4] file1', 'status without selection count';

    # Select file1
    $pane->toggle_selection();
    is $status_text, '[3/4] (1 selected) file2', 'status shows 1 selected';

    # Select file2
    $pane->toggle_selection();
    is $status_text, '[4/4] (2 selected) file3', 'status shows 2 selected';
};

done_testing;
