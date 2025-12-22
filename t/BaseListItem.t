use v5.42;
use utf8;
use experimental 'class';
use Test2::V0;
use Test2::Tools::Mock qw(mock);
use POSIX qw(tzset);
use lib 't/lib';
use DoubleDrive::Test::Time qw(sub_at);

use lib 'lib';
use DoubleDrive::BaseListItem;

BEGIN {
    $ENV{TZ} = 'UTC';
    tzset();
}

# Test subclass implementing BaseListItem abstract methods
class TestListItem :isa(DoubleDrive::BaseListItem) {
    field $basename_value :param = 'test.txt';
    field $stringify_value :param = '/test/test.txt';
    field $is_dir_value :param = false;
    field $stat_value :param = undef;
    field $children_value :param = [];

    method basename() { $basename_value }
    method stringify() { $stringify_value }
    method is_dir() { $is_dir_value }
    method stat() { $stat_value }
    method children() { $children_value }
}

subtest 'size' => sub {
    subtest 'returns size from stat' => sub {
        my $stat_double = mock {} => (
            add => [
                size => sub { 1024 },
            ],
        );

        my $item = TestListItem->new(stat_value => $stat_double);
        is $item->size, 1024, 'returns size from stat';
    };

    subtest 'returns 0 when stat is undef' => sub {
        my $item = TestListItem->new(stat_value => undef);
        is $item->size, 0, 'returns 0 when stat is undef';
    };
};

subtest 'mtime' => sub {
    subtest 'returns mtime from stat' => sub {
        my $expected_mtime = 1_609_459_200;  # 2021-01-01
        my $stat_double = mock {} => (
            add => [
                mtime => sub { $expected_mtime },
            ],
        );

        my $item = TestListItem->new(stat_value => $stat_double);
        is $item->mtime, $expected_mtime, 'returns mtime from stat';
    };

    subtest 'returns 0 when stat is undef' => sub {
        my $item = TestListItem->new(stat_value => undef);
        is $item->mtime, 0, 'returns 0 when stat is undef';
    };
};

subtest 'extname' => sub {
    my $test_cases = [
        # [filename, expected_ext, description]
        ['test.txt',        '.txt',    'regular file with extension'],
        ['archive.tar.gz',  '.gz',     'file with multiple dots (returns last)'],
        ['README',          '',        'file without extension'],
        ['Makefile',        '',        'file without extension (uppercase)'],
        ['.vimrc',          '',        'dotfile without extension'],
        ['.bashrc',         '',        'dotfile without extension'],
        ['.config.yaml',    '.yaml',   'dotfile with extension'],
        ['.git.ignore',     '.ignore', 'dotfile with extension (multiple dots)'],
        ['file.',           '.',       'file ending with dot'],
        ['.',               '',        'dot directory'],
        ['..',              '',        'double dot directory'],
        ['a.b.c.d',         '.d',      'multiple extensions (returns last)'],
        ['foo.TXT',         '.TXT',    'extension with uppercase'],
        ['bar.HTML',        '.HTML',   'extension with uppercase'],
    ];

    for my $case (@$test_cases) {
        my ($filename, $expected, $desc) = @$case;

        my $item = TestListItem->new(basename_value => $filename);
        is $item->extname, $expected, $desc;
    }
};

subtest 'format_size' => sub {
    subtest 'formats bytes' => sub {
        my $stat_double = mock {} => (
            add => [
                size => sub { 100 },
            ],
        );

        my $item = TestListItem->new(stat_value => $stat_double);
        is $item->format_size, ' 100.0B', 'formats bytes';
    };

    subtest 'formats 1KB' => sub {
        my $stat_double = mock {} => (
            add => [
                size => sub { 1024 },
            ],
        );

        my $item = TestListItem->new(stat_value => $stat_double);
        is $item->format_size, '   1.0K', 'formats 1KB';
    };

    subtest 'formats 1MB' => sub {
        my $stat_double = mock {} => (
            add => [
                size => sub { 1024 * 1024 },
            ],
        );

        my $item = TestListItem->new(stat_value => $stat_double);
        is $item->format_size, '   1.0M', 'formats 1MB';
    };

    subtest 'formats 1GB' => sub {
        my $stat_double = mock {} => (
            add => [
                size => sub { 1024 * 1024 * 1024 },
            ],
        );

        my $item = TestListItem->new(stat_value => $stat_double);
        is $item->format_size, '   1.0G', 'formats 1GB';
    };

    subtest 'returns undef when stat is undef' => sub {
        my $item = TestListItem->new(stat_value => undef);
        is $item->format_size, undef, 'returns undef when stat is undef';
    };
};

subtest 'format_mtime' => sub_at {
    subtest 'recent file shows month/day time' => sub {
        # mtime: 2025-01-15 10:30:00 (within one year)
        my $stat_double = mock {} => (
            add => [
                mtime => sub { 1_736_937_000 },
            ],
        );

        my $item = TestListItem->new(stat_value => $stat_double);
        is $item->format_mtime, '01/15 10:30', 'recent file shows month/day time';
    };

    subtest 'old file shows date only' => sub {
        # mtime: 2021-01-01 (over one year ago)
        my $stat_double = mock {} => (
            add => [
                mtime => sub { 1_609_459_200 },
            ],
        );

        my $item = TestListItem->new(stat_value => $stat_double);
        is $item->format_mtime, '2021-01-01', 'old file shows date only';
    };

    subtest 'returns undef when stat is undef' => sub {
        my $item = TestListItem->new(stat_value => undef);
        is $item->format_mtime, undef, 'returns undef when stat is undef';
    };
} '2025-01-15T10:30:00Z';

subtest 'format_name' => sub {
    subtest 'file name formatting' => sub {
        my $item = TestListItem->new(
            basename_value => 'test.txt',
            is_dir_value => false,
        );

        is $item->format_name(10), 'test.txt  ', 'pads short name';
        is $item->format_name(8), 'test.txt', 'exact fit';
        is $item->format_name(5), 'te...', 'truncates long name';
    };

    subtest 'directory with trailing slash' => sub {
        my $item = TestListItem->new(
            basename_value => 'testdir',
            is_dir_value => true,
        );

        is $item->format_name(20), 'testdir/            ', 'directory has trailing slash followed by padding';
    };

    subtest 'unicode width handling' => sub {
        # Japanese characters typically have width of 2
        my $item = TestListItem->new(
            basename_value => '日本語.txt',
            is_dir_value => false,
        );

        # 日本語 = 6 columns (3 chars × 2) + .txt = 4 columns = 10 columns total
        is $item->format_name(10), '日本語.txt', 'exact fit for wide chars';
        is $item->format_name(15), '日本語.txt     ', 'pads wide chars';
        # Width 8: "日本" (4 cols) + "..." (3 cols) + 1 padding = 8
        like $item->format_name(8), qr/^日本\.\.\.\s*$/, 'truncates wide chars with ellipsis';
    };
};

subtest 'format_mode' => sub {
    subtest 'returns placeholder when stat is undef' => sub {
        my $item = TestListItem->new(stat_value => undef);
        is $item->format_mode, '----------', 'returns placeholder when stat is undef';
    };

    subtest 'returns placeholder when mode is undef' => sub {
        my $stat_double = mock {} => (
            add => [
                mode => sub { undef },
            ],
        );

        my $item = TestListItem->new(stat_value => $stat_double);
        is $item->format_mode, '----------', 'returns placeholder when mode is undef';
    };

    subtest 'formats file permissions' => sub {
        # 0644 (-rw-r--r--)
        my $stat_double = mock {} => (
            add => [
                mode => sub { 0644 },
            ],
        );

        my $item = TestListItem->new(
            stat_value => $stat_double,
            is_dir_value => false,
        );
        is $item->format_mode, '-rw-r--r--', 'formats 0644 permissions';
    };

    subtest 'formats directory permissions' => sub {
        # 0755 (drwxr-xr-x)
        my $stat_double = mock {} => (
            add => [
                mode => sub { 0755 },
            ],
        );

        my $item = TestListItem->new(
            stat_value => $stat_double,
            is_dir_value => true,
        );
        is $item->format_mode, 'drwxr-xr-x', 'formats 0755 directory permissions';
    };

    subtest 'formats various permission bits' => sub {
        my $test_cases = [
            # [mode, is_dir, expected, description]
            [0777, false, '-rwxrwxrwx', 'all permissions'],
            [0700, false, '-rwx------', 'owner only'],
            [0070, false, '----rwx---', 'group only'],
            [0007, false, '-------rwx', 'other only'],
            [0000, false, '----------', 'no permissions'],
            [0755, true,  'drwxr-xr-x', 'typical directory'],
            [0600, false, '-rw-------', 'private file'],
        ];

        for my $case (@$test_cases) {
            my ($mode, $is_dir, $expected, $desc) = @$case;

            my $stat_double = mock {} => (
                add => [
                    mode => sub { $mode },
                ],
            );

            my $item = TestListItem->new(
                stat_value => $stat_double,
                is_dir_value => $is_dir,
            );
            is $item->format_mode, $expected, $desc;
        }
    };
};

done_testing;
