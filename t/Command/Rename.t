use v5.42;
use utf8;
use Test2::V0;
use lib 'lib';

my $system_calls;

use DoubleDrive::Command::Rename;
use DoubleDrive::FileListItem;
use Path::Tiny qw(path tempfile tempdir);

# Inline stub classes (no test helper dependency)
{
    package PaneStub;
    use Path::Tiny qw(tempdir);

    sub new {
        my ($class, $files, $current_path) = @_;
        bless {
            files => $files || [],
            current_path => $current_path || tempdir(),
            reload_called => 0,
            clear_selection_called => 0,
        }, $class;
    }

    sub get_files_to_operate {
        my $self = shift;
        return [] unless @{ $self->{files} };
        my @selected = grep { $_->is_selected } @{ $self->{files} };
        return @selected ? \@selected : [ $self->{files}[0] ];
    }
    sub current_path { $_[0]->{current_path} }
    sub reload_directory { $_[0]->{reload_called}++ }
    sub clear_selection { $_[0]->{clear_selection_called}++ }
}

{
    package ContextStub;

    sub new {
        my ($class, $pane) = @_;
        bless { pane => $pane }, $class;
    }
    sub active_pane { $_[0]->{pane} }

    sub on_status_change {
        sub { }
    }
}

# Helper to create a file or directory item
sub make_file {
    my ($name, %opts) = @_;
    my $p;
    if ($opts{is_dir}) {
        $p = tempdir();
    } else {
        # Extract suffix from name (e.g., ".txt" from "file.txt")
        my $suffix = $name =~ /(\.[^.]+)$/ ? $1 : '';
        $p = tempfile(SUFFIX => $suffix);
    }
    my $item = DoubleDrive::FileListItem->new(path => $p);
    $item->toggle_selected() if $opts{selected};
    return $item;
}

subtest 'no files to operate - returns immediately' => sub {
    $system_calls = [];
    my $pane = PaneStub->new([]);
    my $ctx = ContextStub->new($pane);
    my $runner = sub { push @$system_calls, [@_]; return 0 };

    DoubleDrive::Command::Rename->new(
        context => $ctx,
        external_command_runner => $runner,
    )->execute();

    is scalar(@$system_calls), 0, 'system was not called';
    is $pane->{reload_called}, 0, 'reload_directory was not called';
    is $pane->{clear_selection_called}, 0, 'clear_selection was not called';
};

subtest 'rename single file at cursor' => sub {
    $system_calls = [];
    my $file = make_file('test.txt');
    my @files = ($file);
    my $pane = PaneStub->new(\@files);
    my $ctx = ContextStub->new($pane);
    my $runner = sub { push @$system_calls, [@_]; return 0 };

    DoubleDrive::Command::Rename->new(
        context => $ctx,
        external_command_runner => $runner,
    )->execute();

    is scalar(@$system_calls), 1, 'system was called once';
    is $system_calls->[0][0], 'mmv', 'called mmv command';
    is scalar(@{ $system_calls->[0] }), 2, 'mmv called with 1 file path';
    is $system_calls->[0][1], $file->path->basename, 'correct basename passed to mmv';
    is $pane->{reload_called}, 1, 'reload_directory was called';
    is $pane->{clear_selection_called}, 1, 'clear_selection was called';
};

subtest 'rename multiple selected files' => sub {
    $system_calls = [];
    my $file1 = make_file('file1.txt', selected => 1);
    my $file2 = make_file('file2.txt', selected => 1);
    my $file3 = make_file('file3.txt');
    my @files = ($file1, $file2, $file3);
    my $pane = PaneStub->new(\@files);
    my $ctx = ContextStub->new($pane);
    my $runner = sub { push @$system_calls, [@_]; return 0 };

    DoubleDrive::Command::Rename->new(
        context => $ctx,
        external_command_runner => $runner,
    )->execute();

    is scalar(@$system_calls), 1, 'system was called once';
    is $system_calls->[0][0], 'mmv', 'called mmv command';
    is scalar(@{ $system_calls->[0] }), 3, 'mmv called with 2 file paths';
    is $system_calls->[0][1], $file1->path->basename, 'first file basename passed to mmv';
    is $system_calls->[0][2], $file2->path->basename, 'second file basename passed to mmv';
    is $pane->{reload_called}, 1, 'reload_directory was called';
    is $pane->{clear_selection_called}, 1, 'clear_selection was called';
};

subtest 'rename mixed files and directories' => sub {
    $system_calls = [];
    my $file1 = make_file('file1.txt', selected => 1);
    my $dir1 = make_file('dir1', is_dir => 1, selected => 1);
    my $file2 = make_file('file2.txt', selected => 1);
    my @files = ($file1, $dir1, $file2);
    my $pane = PaneStub->new(\@files);
    my $ctx = ContextStub->new($pane);
    my $runner = sub { push @$system_calls, [@_]; return 0 };

    DoubleDrive::Command::Rename->new(
        context => $ctx,
        external_command_runner => $runner,
    )->execute();

    is scalar(@$system_calls), 1, 'system was called once';
    is $system_calls->[0][0], 'mmv', 'called mmv command';
    is scalar(@{ $system_calls->[0] }), 4, 'mmv called with 3 paths (files and directories)';
    is $system_calls->[0][1], $file1->path->basename, 'first file basename passed to mmv';
    is $system_calls->[0][2], $dir1->path->basename, 'directory basename passed to mmv';
    is $system_calls->[0][3], $file2->path->basename, 'second file basename passed to mmv';
    is $pane->{reload_called}, 1, 'reload_directory was called';
    is $pane->{clear_selection_called}, 1, 'clear_selection was called';
};

done_testing;
