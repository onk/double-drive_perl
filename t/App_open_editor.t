use v5.42;
use utf8;
use lib 'lib';

use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Path::Tiny qw(path tempdir);

our $system_calls;
our $system_exit_code;

BEGIN {
    *CORE::GLOBAL::system = sub {
        push @$system_calls, [@_];
        $? = $system_exit_code;
        return $system_exit_code;
    };
}

use DoubleDrive::App;
use DoubleDrive::FileListItem;

# Test doubles
{
    package EditorTestPane;
    sub new($class, %args) { bless \%args, $class }
    sub set_active($self, $active) { }
    sub after_window_attached($self) { }
    sub files($self) { $self->{files} // [] }
    sub selected_index($self) { $self->{selected_index} // 0 }
    sub current_path($self) { $self->{current_path} }
}

{
    package EditorStatusBar;
    sub new($class, %args) { bless {}, $class }
    sub set_text($self, $text) { $self->{last} = $text }
    sub last($self) { $self->{last} }
}

{
    package EditorTickit;
    sub new($class, %args) { bless \%args, $class }
    sub bind_key($self, $key, $cb) { }
    sub later($self, $cb) { $cb->() }
    sub term($self) { bless {}, 'EditorTickitTerm' }
    sub rootwin($self) { bless {}, 'EditorRootwin' }
    sub run($self) { }
    sub stop($self) { }
}

{
    package EditorTickitTerm;
    sub setctl_int($self, $key, $value) { }
    sub get_size($self) { return (24, 80) }
}

{
    package EditorRootwin;
    sub bind_event($self, %args) { return 1 }
    sub unbind_event_id($self, $id) { }
}

sub build_app_with_mocks ($left_pane) {
    my $status_bar = EditorStatusBar->new;
    my $right_pane = EditorTestPane->new;

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
                return EditorTickit->new(%args);
            },
            later => sub { my ($self, $cb) = @_; $cb->() },
        ],
    );

    my $app = DoubleDrive::App->new;

    return ($app, $status_bar, $mocks);
}

subtest 'opens editor for file with success' => sub {
    local $system_calls = [];
    local $system_exit_code = 0;

    my $tmpdir = tempdir;
    my $file_path = path($tmpdir, 'test.txt');
    $file_path->touch;

    my $file_item = DoubleDrive::FileListItem->new(path => $file_path);
    my $left_pane = EditorTestPane->new(
        files => [$file_item],
        selected_index => 0,
        current_path => $tmpdir,
    );

    my ($app, $status_bar, $mocks) = build_app_with_mocks($left_pane);

    $app->open_editor();

    is scalar(@$system_calls), 1, 'system() called once';
    my $cmd = $system_calls->[0];
    is $cmd->[0], 'tmux', 'first arg is tmux';
    is $cmd->[1], 'new-window', 'second arg is new-window';
    is $cmd->[2], '-c', 'third arg is -c';
    is $cmd->[3], $tmpdir->stringify, 'fourth arg is current directory';
    is $cmd->[4], 'zsh', 'fifth arg is zsh';
    is $cmd->[5], '-c', 'sixth arg is -c';
    like $cmd->[6], qr/\$\{=1\}/, 'seventh arg contains zsh expansion';
    is $cmd->[8], 'vim', 'ninth arg is editor (default vim)';
    is $cmd->[9], $file_path->stringify, 'tenth arg is file path';

    like $status_bar->last, qr/Opened editor for/, 'success message shown';
    like $status_bar->last, qr/test\.txt/, 'success message contains filename';
};

subtest 'opens editor with custom EDITOR' => sub {
    local $system_calls = [];
    local $system_exit_code = 0;
    local $ENV{EDITOR} = 'emacs';

    my $tmpdir = tempdir;
    my $file_path = path($tmpdir, 'code.pl');
    $file_path->touch;

    my $file_item = DoubleDrive::FileListItem->new(path => $file_path);
    my $left_pane = EditorTestPane->new(
        files => [$file_item],
        selected_index => 0,
        current_path => $tmpdir,
    );

    my ($app, $status_bar, $mocks) = build_app_with_mocks($left_pane);

    $app->open_editor();

    is $system_calls->[0][8], 'emacs', 'uses $ENV{EDITOR} when set';
};

subtest 'shows error message on system failure' => sub {
    local $system_calls = [];
    local $system_exit_code = 256;    # Exit code 1 (256 = 1 << 8)

    my $tmpdir = tempdir;
    my $file_path = path($tmpdir, 'test.txt');
    $file_path->touch;

    my $file_item = DoubleDrive::FileListItem->new(path => $file_path);
    my $left_pane = EditorTestPane->new(
        files => [$file_item],
        selected_index => 0,
        current_path => $tmpdir,
    );

    my ($app, $status_bar, $mocks) = build_app_with_mocks($left_pane);

    $app->open_editor();

    like $status_bar->last, qr/Failed to open editor/, 'error message shown';
    like $status_bar->last, qr/exit code: 1/, 'error message contains exit code';
};

done_testing;
