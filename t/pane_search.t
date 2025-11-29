use v5.42;

use Test2::V0;
use lib 't/lib';
use DoubleDrive::Test::TempDir qw(temp_dir_with_files);
use DoubleDrive::Test::Mock qw(mock_file_stat capture_widget_text FIXED_MTIME);

use lib 'lib';
use DoubleDrive::Pane;

subtest 'enter_search_mode sets mode and clears state' => sub {
    my $dir = temp_dir_with_files('file1.txt', 'file2.txt');

    my $status_text;
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub { $status_text = shift }
    );

    $pane->enter_search_mode();

    like $status_text, qr{^/ \(no matches\)$}, 'status shows empty search';
};

subtest 'add_search_char matches files and moves cursor' => sub {
    my $dir = temp_dir_with_files('apple.txt', 'banana.txt', 'apricot.txt');

    my $status_text;
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub { $status_text = shift }
    );

    $pane->enter_search_mode();
    $pane->add_search_char('a');
    $pane->add_search_char('p');

    like $status_text, qr{^/ap \(2 matches\)$}, 'status shows 2 matches for "ap"';
    is $pane->selected_index, 0, 'cursor moves to first match (apple)';
};

subtest 'delete_search_char updates matches' => sub {
    my $dir = temp_dir_with_files('apple.txt', 'banana.txt', 'apricot.txt');

    my $status_text;
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub { $status_text = shift }
    );

    $pane->enter_search_mode();
    $pane->add_search_char('a');
    $pane->add_search_char('p');
    $pane->delete_search_char();

    like $status_text, qr{^/a \(3 matches\)$}, 'status shows 3 matches for "a" after deletion';
};

subtest 'delete_search_char does nothing on empty query' => sub {
    my $dir = temp_dir_with_files('file.txt');

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub {}
    );

    $pane->enter_search_mode();

    # Should not error
    ok lives { $pane->delete_search_char() }, 'delete on empty query does not error';
};

subtest 'next_match navigates forward with wrapping' => sub {
    my $dir = temp_dir_with_files('apple.txt', 'banana.txt', 'apricot.txt', 'cherry.txt');

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub {}
    );

    $pane->enter_search_mode();
    $pane->add_search_char('a');

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
        on_status_change => sub {}
    );

    $pane->enter_search_mode();
    $pane->add_search_char('a');

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
        on_status_change => sub {}
    );

    $pane->enter_search_mode();
    $pane->add_search_char('z');

    my $initial_index = $pane->selected_index;
    $pane->next_match();

    is $pane->selected_index, $initial_index, 'cursor does not move with no matches';
};

subtest 'exit_search_mode keeps results for n/N' => sub {
    my $dir = temp_dir_with_files('apple.txt', 'banana.txt', 'apricot.txt');

    my $status_text;
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub { $status_text = shift }
    );

    $pane->enter_search_mode();
    $pane->add_search_char('a');
    $pane->exit_search_mode();

    # Files sorted: apple(0), apricot(1), banana(2)
    # All 3 match "a"
    like $status_text, qr{\[search: a \(3\)\]}, 'status shows retained search results';

    # n/N should still work
    $pane->next_match();
    is $pane->selected_index, 1, 'n navigates to next match after exit (apricot)';
};

subtest 'clear_search resets all state' => sub {
    my $dir = temp_dir_with_files('apple.txt', 'banana.txt');

    my $status_text;
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub { $status_text = shift }
    );

    $pane->enter_search_mode();
    $pane->add_search_char('a');
    $pane->clear_search();

    unlike $status_text, qr{search}, 'status does not show search after clear';

    # next_match should do nothing
    my $initial_index = $pane->selected_index;
    $pane->next_match();
    is $pane->selected_index, $initial_index, 'n does nothing after clear';
};

subtest 'change_directory clears search state' => sub {
    my $dir = temp_dir_with_files('subdir/file.txt', 'apple.txt');

    my $status_text;
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub { $status_text = shift }
    );

    $pane->enter_search_mode();
    $pane->add_search_char('a');

    # Change directory
    $pane->change_directory('subdir');

    unlike $status_text, qr{search}, 'search cleared after directory change';
};

subtest 'search is case-insensitive' => sub {
    my $dir = temp_dir_with_files('Apple.txt', 'BANANA.txt', 'cherry.txt');

    my $status_text;
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub { $status_text = shift }
    );

    $pane->enter_search_mode();
    $pane->add_search_char('a');

    like $status_text, qr{^/a \(2 matches\)$}, 'matches Apple and BANANA (case-insensitive)';
};

subtest 'get_search_status formats correctly' => sub {
    my $dir = temp_dir_with_files('file1.txt', 'file2.txt');

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub {}
    );

    # No search
    is $pane->get_search_status(), '', 'empty when not searching';

    # Active search with matches
    $pane->enter_search_mode();
    $pane->add_search_char('f');
    like $pane->get_search_status(), qr{^/f \(2 matches\)$}, 'active search format';

    # Active search with no matches
    $pane->add_search_char('z');
    is $pane->get_search_status(), '/fz (no matches)', 'no matches format';

    # Exited search
    $pane->delete_search_char();
    $pane->exit_search_mode();
    like $pane->get_search_status(), qr{^ \[search: f \(2\)\]$}, 'retained search format';
};

done_testing;
