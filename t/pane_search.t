use v5.42;
use utf8;

use Test2::V0;
use lib 't/lib';
use DoubleDrive::Test::TempDir qw(temp_dir_with_files);
use DoubleDrive::Test::Mock qw(mock_file_stat capture_widget_text FIXED_MTIME);

use lib 'lib';
use DoubleDrive::Pane;

subtest 'update_search with empty query' => sub {
    my $dir = temp_dir_with_files('file1.txt', 'file2.txt');

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub { }
    );

    my $match_count = $pane->update_search("");
    is $match_count, 0, 'empty query returns 0 matches';
};

subtest 'update_search matches files and moves cursor' => sub {
    my $dir = temp_dir_with_files('apple.txt', 'banana.txt', 'apricot.txt');

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub { }
    );

    my $match_count = $pane->update_search("ap");

    is $match_count, 2, 'returns 2 matches for "ap"';
    is $pane->selected_index, 0, 'cursor moves to first match (apple)';
};

subtest 'update_search with different queries' => sub {
    my $dir = temp_dir_with_files('apple.txt', 'banana.txt', 'apricot.txt');

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub { }
    );

    my $match_count1 = $pane->update_search("ap");
    is $match_count1, 2, '2 matches for "ap"';
    is $pane->selected_index, 0, 'cursor at first match (apple)';

    my $match_count2 = $pane->update_search("a");
    is $match_count2, 3, '3 matches for "a"';
    is $pane->selected_index, 0, 'cursor at first match (apple)';
};

subtest 'next_match navigates forward with wrapping' => sub {
    my $dir = temp_dir_with_files('apple.txt', 'banana.txt', 'apricot.txt', 'cherry.txt');

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub { }
    );

    $pane->update_search('a');

    # Files sorted: apple(0), apricot(1), banana(2), cherry(3)
    # Matches for "a": apple(0), apricot(1), banana(2)
    is $pane->selected_index, 0, 'starts at first match (apple)';

    $pane->next_match();
    is $pane->selected_index, 1, 'moves to second match (apricot)';

    $pane->next_match();
    is $pane->selected_index, 2, 'moves to third match (banana)';

    $pane->next_match();
    is $pane->selected_index, 0, 'wraps to first match (apple)';
};

subtest 'prev_match navigates backward with wrapping' => sub {
    my $dir = temp_dir_with_files('apple.txt', 'banana.txt', 'apricot.txt', 'cherry.txt');

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub { }
    );

    $pane->update_search('a');

    # Files sorted: apple(0), apricot(1), banana(2), cherry(3)
    # Matches for "a": apple(0), apricot(1), banana(2)
    is $pane->selected_index, 0, 'starts at first match (apple)';

    $pane->prev_match();
    is $pane->selected_index, 2, 'wraps to last match (banana)';

    $pane->prev_match();
    is $pane->selected_index, 1, 'moves to previous match (apricot)';

    $pane->prev_match();
    is $pane->selected_index, 0, 'moves to previous match (apple)';
};

subtest 'next_match does nothing with no matches' => sub {
    my $dir = temp_dir_with_files('file1.txt', 'file2.txt');

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub { }
    );

    $pane->update_search('z');

    my $initial_index = $pane->selected_index;
    $pane->next_match();

    is $pane->selected_index, $initial_index, 'cursor does not move with no matches';
};

subtest 'clear_search resets all state' => sub {
    my $dir = temp_dir_with_files('apple.txt', 'banana.txt');

    my $status_text;
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub { $status_text = shift }
    );

    $pane->update_search('a');
    $pane->clear_search();

    unlike $status_text, qr{search}, 'status does not show search after clear';

    # next_match should do nothing
    my $initial_index = $pane->selected_index;
    $pane->next_match();
    is $pane->selected_index, $initial_index, 'n does nothing after clear';
};

subtest 'clear_search clears is_match flags' => sub {
    my $dir = temp_dir_with_files('apple.txt', 'banana.txt', 'cherry.txt');

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub { }
    );

    # Search for 'a' - should match apple and banana
    $pane->update_search('a');

    # Verify some items have is_match = true
    my $files = $pane->files;
    my @matched = grep { $_->is_match } @$files;
    is scalar(@matched), 2, 'two files marked as match after search';

    # Clear search
    $pane->clear_search();

    # Verify all items have is_match = false
    @matched = grep { $_->is_match } @$files;
    is scalar(@matched), 0, 'no files marked as match after clear';
};

subtest 'change_directory clears search state' => sub {
    my $dir = temp_dir_with_files('subdir/file.txt', 'apple.txt');

    my $status_text;
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub { $status_text = shift }
    );

    $pane->update_search('a');

    # Change directory
    my $subdir_item = DoubleDrive::FileListItem->new(path => $dir->child('subdir'));
    $pane->change_directory($subdir_item);

    unlike $status_text, qr{search}, 'search cleared after directory change';
};

subtest 'search is case-insensitive' => sub {
    my $dir = temp_dir_with_files('Apple.txt', 'BANANA.txt', 'cherry.txt');

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub { }
    );

    my $match_count = $pane->update_search('a');

    is $match_count, 2, 'matches Apple and BANANA (case-insensitive)';
};

subtest 'get_search_status formats correctly' => sub {
    my $dir = temp_dir_with_files('file1.txt', 'file2.txt');

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub { }
    );

    # No search
    is $pane->get_search_status(), '', 'empty when not searching';

    # After search with matches
    $pane->update_search('f');
    like $pane->get_search_status(), qr{^ \[search: f \(1/2\)\]$}, 'retained search format with position';

    # After search with no matches
    $pane->update_search('z');
    is $pane->get_search_status(), '', 'empty when no matches';
};

done_testing;
