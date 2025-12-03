use v5.42;
use utf8;

use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Future;

use lib 'lib', 't/lib';
use DoubleDrive::Command::Delete;
use DoubleDrive::CommandContext;
use DoubleDrive::Test::Mock qw(mock_path mock_pane);

subtest 'no files to operate - returns immediately' => sub {
    my $pane = mock_pane(files => []);
    my $confirm_called = 0;
    my $delete_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            delete_files => sub {
                $delete_called++;
                return [];
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $pane,
        opposite_pane => mock_pane(),
        on_status_change => sub {},
        on_confirm => sub { $confirm_called++; Future->done },
        on_alert => sub { Future->done },
    );

    my $future = DoubleDrive::Command::Delete->new(context => $context)->execute();

    ok $future->is_ready, 'future completes immediately';
    is $confirm_called, 0, 'on_confirm was not called';
    is $delete_called, 0, 'delete_files was not called';
    is $pane->reload_called, 0, 'reload_directory was not called';
};

subtest 'single file deletion - message and execution' => sub {
    my $file = mock_path('test.txt');
    my $pane = mock_pane(files => [$file]);

    my $confirm_message;
    my $delete_called = 0;
    my $deleted_files;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            delete_files => sub ($class, $files) {
                $delete_called++;
                $deleted_files = $files;
                return [];  # no failures
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $pane,
        opposite_pane => mock_pane(),
        on_status_change => sub {},
        on_confirm => sub ($msg, $title) {
            $confirm_message = $msg;
            return Future->done;
        },
        on_alert => sub { Future->done },
    );

    my $future = DoubleDrive::Command::Delete->new(context => $context)->execute();

    ok $future->is_ready, 'future completes';
    is $confirm_message, 'Delete test.txt?', 'correct message for single file';
    is $delete_called, 1, 'delete_files was called';
    is scalar(@$deleted_files), 1, 'one file deleted';
    is $deleted_files->[0]->path->stringify, $file->stringify, 'FileManipulator called with correct file';
    is $pane->reload_called, 1, 'reload_directory was called';
};

subtest 'multiple files deletion - message format' => sub {
    my @files = (
        mock_path('file1.txt'),
        mock_path('file2.txt'),
        mock_path('file3.txt'),
    );
    my $pane = mock_pane(files => \@files);

    my $confirm_message;
    my $delete_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            delete_files => sub {
                $delete_called++;
                return [];
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $pane,
        opposite_pane => mock_pane(),
        on_status_change => sub {},
        on_confirm => sub ($msg, $title) {
            $confirm_message = $msg;
            return Future->done;
        },
        on_alert => sub { Future->done },
    );

    my $future = DoubleDrive::Command::Delete->new(context => $context)->execute();

    ok $future->is_ready, 'future completes';
    is $confirm_message, 'Delete 3 files (file1.txt, file2.txt, file3.txt)?',
        'correct message for multiple files';
    is $delete_called, 1, 'delete_files was called';
    is $pane->reload_called, 1, 'reload_directory was called';
};

subtest 'user cancels deletion' => sub {
    my $file = mock_path('test.txt');
    my $pane = mock_pane(files => [$file]);

    my $delete_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            delete_files => sub {
                $delete_called++;
                return [];
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $pane,
        opposite_pane => mock_pane(),
        on_status_change => sub {},
        on_confirm => sub {
            return Future->fail('cancelled by user');
        },
        on_alert => sub { Future->done },
    );

    my $future = DoubleDrive::Command::Delete->new(context => $context)->execute();

    ok $future->is_ready, 'future completes after cancel';
    is $delete_called, 0, 'delete_files was not called';
    is $pane->reload_called, 0, 'reload_directory was not called after cancel';
};

subtest 'deletion fails - shows error dialog' => sub {
    my $file = mock_path('readonly.txt');
    my $pane = mock_pane(files => [$file]);

    my $alert_message;
    my $delete_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            delete_files => sub {
                $delete_called++;
                return [
                    { file => 'readonly.txt', error => 'Permission denied' },
                ];
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $pane,
        opposite_pane => mock_pane(),
        on_status_change => sub {},
        on_confirm => sub { Future->done },
        on_alert => sub ($msg, $title) {
            $alert_message = $msg;
            return Future->done;
        },
    );

    my $future = DoubleDrive::Command::Delete->new(context => $context)->execute();

    ok $future->is_ready, 'future completes after error';
    like $alert_message, qr/Failed to delete:/, 'error message shown';
    like $alert_message, qr/readonly\.txt/, 'includes file name';
    like $alert_message, qr/Permission denied/, 'includes error details';
    is $delete_called, 1, 'delete_files was called';
    is $pane->reload_called, 1, 'reload_directory was still called';
};

subtest 'multiple files with partial failure' => sub {
    my @files = (
        mock_path('file1.txt'),
        mock_path('file2.txt'),
    );
    my $pane = mock_pane(files => \@files);

    my $alert_message;
    my $delete_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            delete_files => sub {
                $delete_called++;
                return [
                    { file => 'file2.txt', error => 'File in use' },
                ];
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $pane,
        opposite_pane => mock_pane(),
        on_status_change => sub {},
        on_confirm => sub { Future->done },
        on_alert => sub ($msg, $title) {
            $alert_message = $msg;
            return Future->done;
        },
    );

    my $future = DoubleDrive::Command::Delete->new(context => $context)->execute();

    ok $future->is_ready, 'future completes';
    like $alert_message, qr/file2\.txt/, 'failed file is reported';
    like $alert_message, qr/File in use/, 'error reason is included';
    is $delete_called, 1, 'delete_files was called';
};

subtest 'unexpected error during deletion' => sub {
    my $file = mock_path('test.txt');
    my $pane = mock_pane(files => [$file]);

    my $alert_message;
    my $delete_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            delete_files => sub {
                $delete_called++;
                die "Unexpected system error";
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $pane,
        opposite_pane => mock_pane(),
        on_status_change => sub {},
        on_confirm => sub { Future->done },
        on_alert => sub ($msg, $title) {
            $alert_message = $msg;
            return Future->done;
        },
    );

    my $future = DoubleDrive::Command::Delete->new(context => $context)->execute();

    ok $future->is_ready, 'future completes after unexpected error';
    like $alert_message, qr/Failed to delete:/, 'error message prefix';
    like $alert_message, qr/Unexpected system error/, 'includes exception message';
    is $delete_called, 1, 'delete_files was called';
};

done_testing;
