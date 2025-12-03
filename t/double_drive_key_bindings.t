use v5.42;
use utf8;

use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Tickit::Test;
use POSIX qw(tzset);
use lib 't/lib';
use DoubleDrive::Test::TempDir qw(temp_dir_with_files);

use lib 'lib';
use DoubleDrive::App;

BEGIN {
    $ENV{TZ} = 'UTC';
    tzset();
}

subtest 'key presses are handled' => sub {
    my $dir = temp_dir_with_files('file1', 'file2', 'file3');

    my $mock_tickit = mk_tickit;
    my $mock = mock 'Tickit' => (
        override => [ new => sub { $mock_tickit } ]
    );

    my $app = DoubleDrive::App->new();

    flush_tickit;
    drain_termlog;

    my $left = $app->left_pane();
    my $right = $app->right_pane();

    # Initial state
    ok $left->is_active, 'left pane is initially active';
    ok !$right->is_active, 'right pane is initially inactive';
    is $left->selected_index, 0, 'left pane selection starts at 0';

    # Test Down key - should move selection down in left pane
    presskey(text => "Down");
    flush_tickit;
    is $left->selected_index, 1, 'left pane selection moved to 1 after Down';

    # Test Up key - should move selection up in left pane
    presskey(text => "Up");
    flush_tickit;
    is $left->selected_index, 0, 'left pane selection back to 0 after Up';

    # Test Tab key (pane switch) - should switch active pane
    presskey(text => "Tab");
    flush_tickit;
    ok !$left->is_active, 'left pane is now inactive after Tab';
    ok $right->is_active, 'right pane is now active after Tab';

    # After Tab, Down should affect the right pane
    is $right->selected_index, 0, 'right pane selection starts at 0';
    presskey(text => "Down");
    flush_tickit;
    is $right->selected_index, 1, 'right pane selection moved to 1 after Down';
    is $left->selected_index, 0, 'left pane selection unchanged';
};

done_testing;
