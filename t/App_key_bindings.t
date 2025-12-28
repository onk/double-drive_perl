use v5.42;
use utf8;
use lib 'lib';

use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Path::Tiny qw(path tempdir);

use DoubleDrive::App;
use DoubleDrive::FileListItem;

# Test doubles
{
    package MockPane;
    sub new($class, %args) { bless \%args, $class }
    sub set_active($self, $active) { }
    sub after_window_attached($self) { }
    sub move_cursor($self, $delta) { push @{$self->{move_cursor_calls}}, $delta }
    sub current_file($self) { $self->{current_file} }
    sub current_path($self) { $self->{current_path} // Path::Tiny::tempdir() }
    sub files($self) { $self->{files} // [] }
}

{
    package MockStatusBar;
    sub new($class, %args) { bless {}, $class }
    sub set_text($self, $text) { }
}

{
    package MockTickit;
    sub new($class, %args) { bless \%args, $class }
    sub bind_key($self, $key, $cb) { }
    sub later($self, $cb) { $cb->() }
    sub term($self) { bless {}, 'MockTerm' }
    sub rootwin($self) { bless {}, 'MockRootwin' }
}

{
    package MockTerm;
    sub setctl_int($self, $key, $value) { }
    sub get_size($self) { return (24, 80) }
}

{
    package MockRootwin;
    sub bind_event($self, %args) { return 1 }
    sub unbind_event_id($self, $id) { }
}

sub build_app_with_key_tracking {
    my %opts = @_;

    my $left_pane = $opts{left_pane} // MockPane->new;
    my $right_pane = $opts{right_pane} // MockPane->new;
    my $status_bar = MockStatusBar->new;

    my $key_bindings = {};

    my $mocks = {};
    $mocks->{layout} = mock 'DoubleDrive::Layout' => (
        override => [
            build => sub {
                return {
                    left_pane => $left_pane,
                    right_pane => $right_pane,
                    float_box => undef,
                    status_bar => $status_bar,
                };
            },
        ],
    );

    $mocks->{tickit} = mock 'Tickit' => (
        override => [
            new => sub {
                my ($class, %args) = @_;
                return MockTickit->new(%args);
            },
            later => sub { my ($self, $cb) = @_; $cb->() },
        ],
    );

    $mocks->{dispatcher} = mock 'DoubleDrive::KeyDispatcher' => (
        override => [
            bind_normal => sub {
                my ($self, $key, $cb) = @_;
                $key_bindings->{$key} = $cb;
            },
            dialog_scope => sub { bless {}, 'MockDialogScope' },
        ],
    );

    $mocks->{cmdline} = mock 'DoubleDrive::CommandLineMode' => (
        override => [
            enter => sub { },
        ],
    );

    my $app = DoubleDrive::App->new;

    return {
        app => $app,
        key_bindings => $key_bindings,
        left_pane => $left_pane,
        right_pane => $right_pane,
        mocks => $mocks,
    };
}

subtest 'all expected keys are registered' => sub {
    my $ctx = build_app_with_key_tracking();
    my $keys = $ctx->{key_bindings};

    is $keys, hash {
        # Navigation
        field j => D();         # down
        field k => D();         # up
        field h => D();         # left pane
        field l => D();         # right pane
        field Up => D();
        field Down => D();
        field Tab => D();       # switch pane
        field g => D();         # top
        field G => D();         # bottom
        field Enter => D();     # enter directory
        field Backspace => D(); # parent directory

        # Selection
        field ' ' => D();       # toggle selection
        field a => D();         # select all

        # Search
        field '/' => D();       # search
        field '*' => D();       # filter
        field n => D();         # next match
        field N => D();         # prev match
        field Escape => D();    # clear search and filter

        # Commands
        field c => D();         # copy
        field d => D();         # delete
        field m => D();         # move
        field e => D();         # open editor
        field K => D();         # mkdir
        field r => D();         # rename
        field v => D();         # view file
        field x => D();         # open tmux window

        # Other
        field s => D();         # sort
        field L => D();         # jump to registered directory
        field q => D();         # quit

        end();
    }, 'all expected keys are registered';
};

subtest 'hjkl navigation bindings work correctly' => sub {
    my $left_pane = MockPane->new(move_cursor_calls => []);
    my $right_pane = MockPane->new(move_cursor_calls => []);

    my $ctx = build_app_with_key_tracking(
        left_pane => $left_pane,
        right_pane => $right_pane,
    );
    my $keys = $ctx->{key_bindings};
    my $app = $ctx->{app};

    # Initially left pane is active
    is $app->active_pane, $left_pane, 'left pane active initially';

    # j should move cursor down on active pane
    $keys->{j}->();
    is $left_pane->{move_cursor_calls}, [1], 'j moves left pane cursor down';

    # k should move cursor up on active pane
    $keys->{k}->();
    is $left_pane->{move_cursor_calls}, [1, -1], 'k moves left pane cursor up';

    # l should switch to right pane when left is active
    $keys->{l}->();
    is $app->active_pane, $right_pane, 'l switches to right pane';

    # h should switch back to left pane when right is active
    $keys->{h}->();
    is $app->active_pane, $left_pane, 'h switches to left pane';
};

subtest 'arrow key navigation' => sub {
    my $left_pane = MockPane->new(move_cursor_calls => []);

    my $ctx = build_app_with_key_tracking(left_pane => $left_pane);
    my $keys = $ctx->{key_bindings};

    $keys->{Down}->();
    is $left_pane->{move_cursor_calls}, [1], 'Down moves cursor';

    $keys->{Up}->();
    is $left_pane->{move_cursor_calls}, [1, -1], 'Up moves cursor';
};

subtest 'Tab switches panes' => sub {
    my $ctx = build_app_with_key_tracking();
    my $keys = $ctx->{key_bindings};
    my $app = $ctx->{app};

    my $left = $ctx->{left_pane};
    my $right = $ctx->{right_pane};

    is $app->active_pane, $left, 'starts with left pane';

    $keys->{Tab}->();
    is $app->active_pane, $right, 'Tab switches to right';

    $keys->{Tab}->();
    is $app->active_pane, $left, 'Tab toggles back to left';
};

done_testing;
