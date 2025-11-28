use v5.42;

use Test2::V0;
use Tickit::Test qw(mk_term_and_window);
use POSIX qw(tzset);
use lib 't/lib';
use DoubleDrive::Test::TempDir qw(temp_dir_with_files);
use DoubleDrive::Test::Mock qw(capture_widget_text mock_file_stat);

use lib 'lib';
use DoubleDrive::Pane;

# Note: This test uses capture_widget_text() instead of Tickit::Test's is_display()
# to focus on the TextWidget content without Frame borders. This makes the test
# more focused on the Pane's text rendering logic rather than the full widget layout.

BEGIN {
    $ENV{TZ} = 'UTC';
    tzset();
}

my (undef, $test_window) = mk_term_and_window(lines => 5, cols => 24);

subtest 'initial render shows parent and sorted files' => sub {
    my $dir = temp_dir_with_files('B', 'a');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(path => $dir);
    ok @$texts, 'render called on init';

    my @lines = split /\n/, $texts->[-1];
    is $lines[0], '> ../           0.0B  01/15 10:30', 'parent selected first';
    is $lines[1], '  a             0.0B  01/15 10:30', 'a is second';
    is $lines[2], '  B             0.0B  01/15 10:30', 'B is third';
};

subtest 'selection moves and stops at bounds' => sub {
    my $dir = temp_dir_with_files('file');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(path => $dir);

    @$texts = ();
    $pane->move_selection(1);
    my @lines = split /\n/, $texts->[-1];
    is $lines[0], '  ../           0.0B  01/15 10:30', 'parent now unselected';
    is $lines[1], '> file          0.0B  01/15 10:30', 'file is selected';

    $pane->move_selection(10); # out of range
    is scalar(@$texts), 1, 'no extra render when selection would go out of bounds';
};

subtest 'enter_selected descends into directory and resets selection' => sub {
    my $dir = temp_dir_with_files('sub/file1', 'sub/file2');
    my ($texts, $mock_widget) = capture_widget_text($test_window);
    my $mock_stat = mock_file_stat();

    my $pane = DoubleDrive::Pane->new(path => $dir);
    $pane->move_selection(1);    # select subdir
    $pane->enter_selected();

    my @lines = split /\n/, $texts->[-1];
    is $lines[0], '> ../           0.0B  01/15 10:30', 'selection reset to parent';
    is $lines[1], '  file1         0.0B  01/15 10:30', 'file1 in subdirectory';
    is $lines[2], '  file2         0.0B  01/15 10:30', 'file2 in subdirectory';
};

done_testing;
