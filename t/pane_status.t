use v5.42;
use utf8;

use Test2::V0;
use lib 't/lib';
use DoubleDrive::Test::TempDir qw(temp_dir_with_files);

use lib 'lib';
use DoubleDrive::Pane;

subtest 'status_text returns formatted status' => sub {
    my $dir = temp_dir_with_files('file1.txt', 'file2.txt');

    my $status_text;
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub { $status_text = shift }
    );

    $pane->set_active(1);    # trigger callback once widgets are initialized

    ok $status_text, 'status text is not empty';
    like $status_text, qr/\[1\/2\]/, 'status contains position info (1 of 2: file1, file2)';
};

subtest 'status callback is called on move_cursor' => sub {
    my $dir = temp_dir_with_files('file1.txt', 'file2.txt');

    my $callback_called = 0;
    my $callback_text;

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub {
            $callback_called++;
            $callback_text = shift;
        }
    );

    $callback_called = 0;    # Reset after initialization
    $pane->move_cursor(1);

    is $callback_called, 1, 'callback called once';
    ok $callback_text, 'callback received text';
    like $callback_text, qr/\[2\/2\]/, 'status shows updated position';
};

subtest 'status callback is called on change_directory' => sub {
    my $dir = temp_dir_with_files('subdir/file1.txt');

    my $callback_called = 0;
    my $callback_text;

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub {
            $callback_called++;
            $callback_text = shift;
        }
    );

    $callback_called = 0;    # Reset after initialization
    # Enter subdir (only entry)
    $pane->enter_selected();

    is $callback_called, 1, 'callback called after directory change';
    ok $callback_text, 'callback received text';
};

subtest 'status callback is called on set_active' => sub {
    my $dir = temp_dir_with_files('file1.txt');

    my $callback_called = 0;

    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        on_status_change => sub {
            $callback_called++;
        }
    );

    $pane->set_active(1);

    is $callback_called, 1, 'callback called when set to active';

    # Setting to inactive should not call callback
    $pane->set_active(0);

    is $callback_called, 1, 'callback not called when set to inactive';
};

subtest 'status_text shows directory with trailing slash' => sub {
    my $dir = temp_dir_with_files('testdir/dummy');

    my $status_text;
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub { $status_text = shift }
    );

    $pane->set_active(1);
    like $status_text, qr/testdir\/$/, 'directory shows trailing slash';
};

subtest 'status_text format is position and name' => sub {
    my $dir = temp_dir_with_files('file.txt');

    my $status_text;
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub { $status_text = shift }
    );

    $pane->set_active(1);
    like $status_text, qr/^\[1\/1\] file\.txt$/, 'status shows [position/total] filename format';
};

subtest 'status_text is [0/0] for empty directory' => sub {
    my $dir = temp_dir_with_files();    # empty

    my $status_text;
    my $pane = DoubleDrive::Pane->new(
        path => $dir,
        is_active => 1,
        on_status_change => sub { $status_text = shift }
    );

    $pane->set_active(1);
    is $status_text, '[0/0]', 'empty directory reports [0/0]';
};

done_testing;
