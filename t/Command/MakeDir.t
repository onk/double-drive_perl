use v5.42;
use utf8;

use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Path::Tiny qw(path tempdir);

use lib 'lib', 't/lib';
use DoubleDrive::Command::MakeDir;
use DoubleDrive::CommandContext;
use DoubleDrive::Test::Mock qw(mock_pane);

subtest 'empty directory name' => sub {
    my $tmpdir = tempdir;
    my $pane = mock_pane(current_path => $tmpdir);

    my $status_message;
    my $cmdline_mode = mock {} => (
        add => [
            enter => sub ($self, $callbacks) {
                $callbacks->{on_execute}->('');
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $pane,
        opposite_pane => mock_pane(),
        on_status_change => sub ($msg) {
            $status_message = $msg;
        },
        on_confirm => sub { die "should not be called" },
        on_alert => sub { die "should not be called" },
    );

    DoubleDrive::Command::MakeDir->new(
        context => $context,
        cmdline_mode => $cmdline_mode,
    )->execute();

    is $status_message, 'Directory name cannot be empty', 'shows error for empty name';
    is $pane->change_directory_called, 0, 'change_directory was not called';
};

subtest 'directory name contains slash' => sub {
    my $tmpdir = tempdir;
    my $pane = mock_pane(current_path => $tmpdir);

    my $status_message;
    my $cmdline_mode = mock {} => (
        add => [
            enter => sub ($self, $callbacks) {
                $callbacks->{on_execute}->('foo/bar');
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $pane,
        opposite_pane => mock_pane(),
        on_status_change => sub ($msg) {
            $status_message = $msg;
        },
        on_confirm => sub { die "should not be called" },
        on_alert => sub { die "should not be called" },
    );

    DoubleDrive::Command::MakeDir->new(
        context => $context,
        cmdline_mode => $cmdline_mode,
    )->execute();

    is $status_message, "Directory name cannot contain '/'", 'shows error for slash';
    is $pane->change_directory_called, 0, 'change_directory was not called';
};

subtest 'directory already exists' => sub {
    my $tmpdir = tempdir;
    my $existing_dir = $tmpdir->child('existing');
    $existing_dir->mkpath;

    my $pane = mock_pane(current_path => $tmpdir);

    my $status_message;
    my $cmdline_mode = mock {} => (
        add => [
            enter => sub ($self, $callbacks) {
                $callbacks->{on_execute}->('existing');
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $pane,
        opposite_pane => mock_pane(),
        on_status_change => sub ($msg) {
            $status_message = $msg;
        },
        on_confirm => sub { die "should not be called" },
        on_alert => sub { die "should not be called" },
    );

    DoubleDrive::Command::MakeDir->new(
        context => $context,
        cmdline_mode => $cmdline_mode,
    )->execute();

    is $status_message, "Directory 'existing' already exists", 'shows error for existing dir';
    is $pane->change_directory_called, 0, 'change_directory was not called';
};

subtest 'successfully create directory and change to it' => sub {
    my $tmpdir = tempdir;
    my $pane = mock_pane(current_path => $tmpdir);

    my $cmdline_mode = mock {} => (
        add => [
            enter => sub ($self, $callbacks) {
                $callbacks->{on_execute}->('newdir');
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $pane,
        opposite_pane => mock_pane(),
        on_status_change => sub {},
        on_confirm => sub { die "should not be called" },
        on_alert => sub { die "should not be called" },
    );

    DoubleDrive::Command::MakeDir->new(
        context => $context,
        cmdline_mode => $cmdline_mode,
    )->execute();

    my $new_dir = $tmpdir->child('newdir');
    ok $new_dir->exists, 'directory was created';
    ok $new_dir->is_dir, 'created path is a directory';
    is $pane->change_directory_called, 1, 'change_directory was called';
    is $pane->change_directory_arg, $new_dir->stringify, 'changed to absolute path of new directory';
};

subtest 'create directory with unicode name' => sub {
    my $tmpdir = tempdir;
    my $pane = mock_pane(current_path => $tmpdir);

    my $cmdline_mode = mock {} => (
        add => [
            enter => sub ($self, $callbacks) {
                $callbacks->{on_execute}->('日本語ディレクトリ');
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $pane,
        opposite_pane => mock_pane(),
        on_status_change => sub {},
        on_confirm => sub { die "should not be called" },
        on_alert => sub { die "should not be called" },
    );

    DoubleDrive::Command::MakeDir->new(
        context => $context,
        cmdline_mode => $cmdline_mode,
    )->execute();

    my $new_dir = $tmpdir->child('日本語ディレクトリ');
    ok $new_dir->exists, 'unicode directory was created';
    ok $new_dir->is_dir, 'created path is a directory';
    is $pane->change_directory_called, 1, 'change_directory was called';
};

subtest 'mkdir fails with permission error' => sub {
    my $tmpdir = tempdir;
    my $readonly_dir = $tmpdir->child('readonly');
    $readonly_dir->mkpath;
    chmod 0444, $readonly_dir->stringify;

    my $pane = mock_pane(current_path => $readonly_dir);

    my $status_message;
    my $cmdline_mode = mock {} => (
        add => [
            enter => sub ($self, $callbacks) {
                $callbacks->{on_execute}->('forbidden');
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $pane,
        opposite_pane => mock_pane(),
        on_status_change => sub ($msg) {
            $status_message = $msg;
        },
        on_confirm => sub { die "should not be called" },
        on_alert => sub { die "should not be called" },
    );

    DoubleDrive::Command::MakeDir->new(
        context => $context,
        cmdline_mode => $cmdline_mode,
    )->execute();

    like $status_message, qr/Failed to create directory/, 'shows error message';
    is $pane->change_directory_called, 0, 'change_directory was not called';

    # Cleanup: tempdir auto-removes directories, but needs write permission to do so
    chmod 0755, $readonly_dir->stringify;
};

done_testing;
