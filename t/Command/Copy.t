use v5.42;
use utf8;

use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Future;

use lib 'lib', 't/lib';
use DoubleDrive::Command::Copy;
use DoubleDrive::CommandContext;
use DoubleDrive::Test::Mock qw(mock_path mock_pane);

subtest 'no files to operate - returns immediately' => sub {
    my $pane = mock_pane(files => []);
    my $confirm_called = 0;
    my $copy_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            copy_files => sub {
                $copy_called++;
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

    my $future = DoubleDrive::Command::Copy->new(context => $context)->execute();

    ok $future->is_ready, 'future completes immediately';
    is $confirm_called, 0, 'on_confirm was not called';
    is $copy_called, 0, 'copy_files was not called';
    is $pane->reload_called, 0, 'reload_directory was not called';
};

subtest 'copy to same directory - guard check' => sub {
    my $src_path = mock_path('/home/user/src');
    my $file = mock_path('test.txt');
    my $active_pane = mock_pane(files => [$file], current_path => $src_path);
    my $opposite_pane = mock_pane(current_path => $src_path);

    my $status_message;
    my $copy_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            copy_files => sub {
                $copy_called++;
                return [];
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $active_pane,
        opposite_pane => $opposite_pane,
        on_status_change => sub ($msg) {
            $status_message = $msg;
        },
        on_confirm => sub { Future->done },
        on_alert => sub { Future->done },
    );

    my $future = DoubleDrive::Command::Copy->new(context => $context)->execute();

    ok $future->is_ready, 'future completes';
    is $status_message, 'Copy skipped: source and destination are the same',
        'status message shows skip reason';
    is $copy_called, 0, 'copy_files was not called';
    is $opposite_pane->reload_called, 0, 'reload_directory was not called';
};

subtest 'copy into self - guard check' => sub {
    my $file = mock_path('parent_dir');
    my $active_pane = mock_pane(files => [$file]);
    my $dest_path = mock_path('/home/user/parent_dir/subdir');
    my $opposite_pane = mock_pane(current_path => $dest_path);

    my $status_message;
    my $copy_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            copy_into_self => sub ($class, $files, $dest) {
                return 1;  # true - copying into self
            },
            copy_files => sub {
                $copy_called++;
                return [];
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $active_pane,
        opposite_pane => $opposite_pane,
        on_status_change => sub ($msg) {
            $status_message = $msg;
        },
        on_confirm => sub { Future->done },
        on_alert => sub { Future->done },
    );

    my $future = DoubleDrive::Command::Copy->new(context => $context)->execute();

    ok $future->is_ready, 'future completes';
    is $status_message, 'Copy skipped: destination is inside source',
        'status message shows skip reason';
    is $copy_called, 0, 'copy_files was not called';
    is $opposite_pane->reload_called, 0, 'reload_directory was not called';
};

subtest 'single file copy without overwrite' => sub {
    my $file = mock_path('test.txt');
    my $active_pane = mock_pane(files => [$file]);
    my $opposite_pane = mock_pane(current_path => mock_path('/dest'));

    my $confirm_called = 0;
    my $copy_called = 0;
    my $copied_files;
    my $dest_path;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            copy_into_self => sub {
                return 0;  # not copying into self
            },
            overwrite_targets => sub ($class, $files, $dest) {
                return [];  # no existing files
            },
            copy_files => sub ($class, $files, $dest) {
                $copy_called++;
                $copied_files = $files;
                $dest_path = $dest;
                return [];  # no failures
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $active_pane,
        opposite_pane => $opposite_pane,
        on_status_change => sub {},
        on_confirm => sub {
            $confirm_called++;
            return Future->done;
        },
        on_alert => sub { Future->done },
    );

    my $future = DoubleDrive::Command::Copy->new(context => $context)->execute();

    ok $future->is_ready, 'future completes';
    is $confirm_called, 0, 'on_confirm was not called (no overwrite)';
    is $copy_called, 1, 'copy_files was called';
    is $copied_files, [$file], 'FileManipulator called with correct files';
    is $dest_path->stringify, '/dest', 'destination path is correct';
    is $opposite_pane->reload_called, 1, 'reload_directory was called';
};

subtest 'single file copy with overwrite - confirmation message' => sub {
    my $file = mock_path('test.txt');
    my $active_pane = mock_pane(files => [$file]);
    my $opposite_pane = mock_pane(current_path => mock_path('/dest'));

    my $confirm_message;
    my $copy_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            copy_into_self => sub { return 0 },
            overwrite_targets => sub {
                return ['test.txt'];  # file exists
            },
            copy_files => sub {
                $copy_called++;
                return [];
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $active_pane,
        opposite_pane => $opposite_pane,
        on_status_change => sub {},
        on_confirm => sub ($msg, $title) {
            $confirm_message = $msg;
            return Future->done;
        },
        on_alert => sub { Future->done },
    );

    my $future = DoubleDrive::Command::Copy->new(context => $context)->execute();

    ok $future->is_ready, 'future completes';
    is $confirm_message, 'Overwrite test.txt?', 'correct message for single file overwrite';
    is $copy_called, 1, 'copy_files was called';
    is $opposite_pane->reload_called, 1, 'reload_directory was called';
};

subtest 'multiple files copy with partial overwrite' => sub {
    my @files = (
        mock_path('file1.txt'),
        mock_path('file2.txt'),
        mock_path('file3.txt'),
    );
    my $active_pane = mock_pane(files => \@files);
    my $opposite_pane = mock_pane(current_path => mock_path('/dest'));

    my $confirm_message;
    my $copy_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            copy_into_self => sub { return 0 },
            overwrite_targets => sub {
                return ['file1.txt', 'file3.txt'];  # 2 files exist
            },
            copy_files => sub {
                $copy_called++;
                return [];
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $active_pane,
        opposite_pane => $opposite_pane,
        on_status_change => sub {},
        on_confirm => sub ($msg, $title) {
            $confirm_message = $msg;
            return Future->done;
        },
        on_alert => sub { Future->done },
    );

    my $future = DoubleDrive::Command::Copy->new(context => $context)->execute();

    ok $future->is_ready, 'future completes';
    like $confirm_message, qr/Copy 3 files \(file1\.txt, file2\.txt, file3\.txt\)\?/,
        'message shows all files to copy';
    like $confirm_message, qr/2 file\(s\) will be overwritten: file1\.txt, file3\.txt/,
        'message shows files that will be overwritten';
    is $copy_called, 1, 'copy_files was called';
    is $opposite_pane->reload_called, 1, 'reload_directory was called';
};

subtest 'user cancels copy' => sub {
    my $file = mock_path('test.txt');
    my $active_pane = mock_pane(files => [$file]);
    my $opposite_pane = mock_pane(current_path => mock_path('/dest'));

    my $copy_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            copy_into_self => sub { return 0 },
            overwrite_targets => sub {
                return ['test.txt'];
            },
            copy_files => sub {
                $copy_called++;
                return [];
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $active_pane,
        opposite_pane => $opposite_pane,
        on_status_change => sub {},
        on_confirm => sub {
            return Future->fail('cancelled by user');
        },
        on_alert => sub { Future->done },
    );

    my $future = DoubleDrive::Command::Copy->new(context => $context)->execute();

    ok $future->is_ready, 'future completes after cancel';
    is $copy_called, 0, 'copy_files was not called';
    is $opposite_pane->reload_called, 0, 'reload_directory was not called after cancel';
};

subtest 'copy fails - shows error dialog' => sub {
    my $file = mock_path('readonly.txt');
    my $active_pane = mock_pane(files => [$file]);
    my $opposite_pane = mock_pane(current_path => mock_path('/dest'));

    my $alert_message;
    my $copy_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            copy_into_self => sub { return 0 },
            overwrite_targets => sub {
                return [];
            },
            copy_files => sub {
                $copy_called++;
                return [
                    { file => 'readonly.txt', error => 'Permission denied' },
                ];
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $active_pane,
        opposite_pane => $opposite_pane,
        on_status_change => sub {},
        on_confirm => sub { Future->done },
        on_alert => sub ($msg, $title) {
            $alert_message = $msg;
            return Future->done;
        },
    );

    my $future = DoubleDrive::Command::Copy->new(context => $context)->execute();

    ok $future->is_ready, 'future completes after error';
    like $alert_message, qr/Failed to copy:/, 'error message shown';
    like $alert_message, qr/readonly\.txt/, 'includes file name';
    like $alert_message, qr/Permission denied/, 'includes error details';
    is $copy_called, 1, 'copy_files was called';
    is $opposite_pane->reload_called, 1, 'reload_directory was still called';
};

subtest 'multiple files with partial failure' => sub {
    my @files = (
        mock_path('file1.txt'),
        mock_path('file2.txt'),
    );
    my $active_pane = mock_pane(files => \@files);
    my $opposite_pane = mock_pane(current_path => mock_path('/dest'));

    my $alert_message;
    my $copy_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            copy_into_self => sub { return 0 },
            overwrite_targets => sub {
                return [];
            },
            copy_files => sub {
                $copy_called++;
                return [
                    { file => 'file2.txt', error => 'Disk full' },
                ];
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $active_pane,
        opposite_pane => $opposite_pane,
        on_status_change => sub {},
        on_confirm => sub { Future->done },
        on_alert => sub ($msg, $title) {
            $alert_message = $msg;
            return Future->done;
        },
    );

    my $future = DoubleDrive::Command::Copy->new(context => $context)->execute();

    ok $future->is_ready, 'future completes';
    like $alert_message, qr/file2\.txt/, 'failed file is reported';
    like $alert_message, qr/Disk full/, 'error reason is included';
    is $copy_called, 1, 'copy_files was called';
};

subtest 'unexpected error during copy' => sub {
    my $file = mock_path('test.txt');
    my $active_pane = mock_pane(files => [$file]);
    my $opposite_pane = mock_pane(current_path => mock_path('/dest'));

    my $alert_message;
    my $copy_called = 0;

    my $file_manipulator_mock = mock 'DoubleDrive::FileManipulator' => (
        override => [
            copy_into_self => sub { return 0 },
            overwrite_targets => sub {
                return [];
            },
            copy_files => sub {
                $copy_called++;
                die "Unexpected system error";
            },
        ],
    );

    my $context = DoubleDrive::CommandContext->new(
        active_pane => $active_pane,
        opposite_pane => $opposite_pane,
        on_status_change => sub {},
        on_confirm => sub { Future->done },
        on_alert => sub ($msg, $title) {
            $alert_message = $msg;
            return Future->done;
        },
    );

    my $future = DoubleDrive::Command::Copy->new(context => $context)->execute();

    ok $future->is_ready, 'future completes after unexpected error';
    like $alert_message, qr/Failed to copy:/, 'error message prefix';
    like $alert_message, qr/Unexpected system error/, 'includes exception message';
    is $copy_called, 1, 'copy_files was called';
};

done_testing;
