use v5.42;
use utf8;
use lib 'lib';

use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Path::Tiny qw(path tempdir);
use JSON::PP qw(encode_json);

use DoubleDrive::App;
# Stub classes to keep App construction lightweight in tests
{
    package JumpTestPane;
    sub new($class, %args) { bless \%args, $class }
    sub set_active($self, $active) { }
    sub after_window_attached($self) { }
    sub change_directory($self, $path) { $self->{last_change} = $path }
    sub last_change($self) { $self->{last_change} }
}

{
    package JumpStatusBar;
    sub new($class, %args) { bless {}, $class }
    sub set_text($self, $text) { $self->{last} = $text }
    sub last($self) { $self->{last} }
}

{
    package JumpTickit;
    sub new($class, %args) { bless \%args, $class }
    sub bind_key($self, $key, $cb) { }
    sub later($self, $cb) { $cb->() }
    sub term($self) { bless {}, 'JumpTickitTerm' }
    sub rootwin($self) { bless {}, 'JumpRootwin' }
    sub run($self) { }
    sub stop($self) { }
}

{
    package JumpFloatBox;
    sub new($class) { bless {}, $class }
    sub add_float($self, %args) { return bless {}, 'JumpFloat' }
}

{
    package JumpFloat;
    sub remove($self) { }
}

{
    package JumpDialogInstance;
    sub new($class) { bless {}, $class }
    sub show($self) { }
}

{
    package JumpTickitTerm;
    sub setctl_int($self, $key, $value) { }
    sub get_size($self) { return (24, 80) }
}

{
    package JumpRootwin;
    sub bind_event($self, %args) { return 1 }
    sub unbind_event_id($self, $id) { }
}

sub write_config ($config_home, $payload) {
    my $config_file = path($config_home, 'double_drive', 'config.json');
    $config_file->parent->mkpath;
    $config_file->spew_utf8(encode_json($payload));
}

sub build_app_with_mocks ($dialog_args_ref) {
    my $status_bar = JumpStatusBar->new;
    my $left_pane = JumpTestPane->new;
    my $right_pane = JumpTestPane->new;
    my $float_box = JumpFloatBox->new;

    my $mocks = {};
    $mocks->{layout} = mock 'DoubleDrive::Layout' => (
        override => [
            build => sub {
                return {
                    left_pane => $left_pane,
                    right_pane => $right_pane,
                    float_box => $float_box,
                    status_bar => $status_bar,
                };
            },
        ],
    );

    $mocks->{tickit} = mock 'Tickit' => (
        override => [
            new => sub {
                my ($class, %args) = @_;
                return JumpTickit->new(%args);
            },
            later => sub { my ($self, $cb) = @_; $cb->() },
        ],
    );

    $mocks->{dialog} = mock 'DoubleDrive::Dialog::DirectoryJumpDialog' => (
        override => [
            new => sub {
                my ($class, %args) = @_;
                $$dialog_args_ref = \%args;
                return JumpDialogInstance->new;
            },
        ],
    );

    my $app = DoubleDrive::App->new;

    return ($app, $left_pane, $status_bar, $mocks);
}

subtest 'jumps to configured directory with tilde expansion' => sub {
    my $config_home = tempdir;
    local $ENV{XDG_CONFIG_HOME} = $config_home;
    local $ENV{XDG_STATE_HOME} = tempdir;
    local $ENV{HOME} = $config_home->stringify;

    my $target = path($ENV{HOME}, 'jump_target')->absolute;
    $target->mkpath;

    write_config($config_home, {
        registered_directories => [
            { name => 'jump', path => $target->stringify, key => 'j' },
        ],
    });

    my $dialog_args;
    my ($app, $left_pane, $status_bar, $mocks) = build_app_with_mocks(\$dialog_args);

    $app->jump_to_registered_directory();

    ok $dialog_args, 'dialog instantiated with registered directories';
    is $dialog_args->{directories}[0]{path}, $target->stringify, 'dialog gets configured path';

    $dialog_args->{on_execute}->($dialog_args->{directories}[0]{path});

    is $left_pane->last_change, $target->stringify, 'pane changed to configured directory';
};

subtest 'missing config shows status message' => sub {
    my $config_home = tempdir;
    local $ENV{XDG_CONFIG_HOME} = $config_home;
    local $ENV{XDG_STATE_HOME} = tempdir;

    my $dialog_args;
    my ($app, $left_pane, $status_bar, $mocks) = build_app_with_mocks(\$dialog_args);

    $app->jump_to_registered_directory();

    is $status_bar->last, "No registered directories configured", 'status message shown for missing config';
    ok !$dialog_args, 'dialog not shown when no entries';
    ok !$left_pane->last_change, 'pane not changed';
};

done_testing;
