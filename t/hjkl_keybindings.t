use v5.42;
use utf8;
use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Tickit::Test qw(mk_tickit presskey flush_tickit);
use POSIX qw(tzset);
use lib 'lib';
use DoubleDrive::App;

BEGIN {
    $ENV{TZ} = 'UTC';
    tzset();
}

subtest 'hjkl keybindings using real layout and mocked Tickit' => sub {
    my $mock_tickit = mk_tickit;
    my $mock = mock 'Tickit' => (
        override => [ new => sub { $mock_tickit } ]
    );

    my $app = DoubleDrive::App->new();

    flush_tickit;

    my $left  = $app->left_pane;
    my $right = $app->right_pane;

    ok $left->is_active, 'left pane is initially active';
    is $left->selected_index, 0, 'left pane selection starts at 0';

    # j -> move down
    presskey(text => 'j');
    flush_tickit;
    is $left->selected_index, 1, 'j moves selection down';

    # k -> move up
    presskey(text => 'k');
    flush_tickit;
    is $left->selected_index, 0, 'k moves selection up';

    # l -> switch to right when left active
    presskey(text => 'l');
    flush_tickit;
    ok !$left->is_active && $right->is_active, 'l switches to right when left was active';

    # h -> switch back to left when right active
    presskey(text => 'h');
    flush_tickit;
    ok $left->is_active && !$right->is_active, 'h switches to left when right was active';
};

done_testing();
