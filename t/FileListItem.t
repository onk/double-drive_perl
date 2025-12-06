use v5.42;
use utf8;
use Test2::V0;
use Test2::Tools::Mock qw(mock);
use POSIX qw(tzset);
use lib 't/lib';
use DoubleDrive::Test::Time qw(sub_at);
use Path::Tiny;
use File::Temp qw(tempdir);

use lib 'lib';
use DoubleDrive::FileListItem;

BEGIN {
    $ENV{TZ} = 'UTC';
    tzset();
}

subtest 'construction' => sub {
    my $path = path('/tmp/test.txt');
    my $item = DoubleDrive::FileListItem->new(path => $path);

    is $item->path, $path, 'path stored';
    is $item->is_selected, false, 'not selected by default';
    is $item->is_match, false, 'not match by default';
};

subtest 'toggle_selected' => sub {
    my $item = DoubleDrive::FileListItem->new(path => path('/tmp/test.txt'));

    is $item->is_selected, false, 'initially false';

    $item->toggle_selected();
    is $item->is_selected, true, 'toggled to true';

    $item->toggle_selected();
    is $item->is_selected, false, 'toggled back to false';
};

subtest 'set_match' => sub {
    my $item = DoubleDrive::FileListItem->new(path => path('/tmp/test.txt'));

    is $item->is_match, false, 'initially false';

    $item->set_match(true);
    is $item->is_match, true, 'set to true';

    $item->set_match(false);
    is $item->is_match, false, 'set to false';
};

subtest 'is_dir and stat' => sub {
    my $tempdir = tempdir(CLEANUP => 1);
    my $file = path($tempdir)->child('test.txt');
    $file->spew("test");

    my $file_item = DoubleDrive::FileListItem->new(path => $file);
    ok !$file_item->is_dir, 'file is not dir';
    ok defined($file_item->stat), 'stat returns value';

    my $dir_item = DoubleDrive::FileListItem->new(path => path($tempdir));
    ok $dir_item->is_dir, 'dir is dir';
};

subtest 'basename and stringify' => sub {
    my $tempdir = path(tempdir(CLEANUP => 1));
    my $file = $tempdir->child('test.txt');
    $file->touch;

    my @children = $tempdir->children;
    my $item = DoubleDrive::FileListItem->new(path => $children[0]);

    is $item->basename, 'test.txt', 'basename';
    ok utf8::is_utf8($item->basename), 'basename is internal string';
    ok utf8::is_utf8($item->stringify), 'stringify is internal string';
};

subtest 'NFC normalization' => sub {
    use Unicode::Normalize qw(NFD NFC);

    my $tempdir = path(tempdir(CLEANUP => 1));

    # Create filename in NFD form (as macOS does)
    my $nfd_filename = NFD('ポ') . '.txt';  # ポ in NFD = U+30DB + U+309A
    my $file = $tempdir->child($nfd_filename);
    $file->touch;

    # Get the file from children() to simulate real usage
    my @children = $tempdir->children;
    is scalar(@children), 1, 'one file created';

    my $item = DoubleDrive::FileListItem->new(path => $children[0]);
    my $base = $item->basename;

    ok utf8::is_utf8($base), 'internal string';

    # basename should be NFC normalized
    my $expected_nfc = NFC('ポ') . '.txt';  # ポ in NFC = U+30DD
    is $base, $expected_nfc, 'NFD -> NFC normalized';
    isnt $base, $nfd_filename, 'not the same as NFD input';
};

subtest 'format_size' => sub {
    my $tempdir = path(tempdir(CLEANUP => 1));
    my $file = $tempdir->child('test.txt');

    $file->spew('x' x 1024);
    my @children = $tempdir->children;
    my $item = DoubleDrive::FileListItem->new(path => $children[0]);

    is $item->format_size, '   1.0K', 'formats 1KB file';

    $file->spew('x' x 100);
    @children = $tempdir->children;
    $item = DoubleDrive::FileListItem->new(path => $children[0]);
    is $item->format_size, ' 100.0B', 'formats bytes';
};

subtest 'format_mtime' => sub_at {
    my $tempdir = path(tempdir(CLEANUP => 1));
    my $file = $tempdir->child('test.txt');
    $file->spew('test');

    # Set mtime to 2025-01-15 10:30:00 (within one year)
    utime 1_736_937_000, 1_736_937_000, $file->stringify;

    my @children = $tempdir->children;
    my $item = DoubleDrive::FileListItem->new(path => $children[0]);

    is $item->format_mtime, '01/15 10:30', 'recent file shows month/day time';

    # Set mtime to 2021-01-01 (over one year ago)
    utime 1_609_459_200, 1_609_459_200, $file->stringify;

    @children = $tempdir->children;
    $item = DoubleDrive::FileListItem->new(path => $children[0]);

    is $item->format_mtime, '2021-01-01', 'old file shows date only';
} '2025-01-15T10:30:00Z';

subtest 'format_name' => sub {
    my $tempdir = path(tempdir(CLEANUP => 1));
    my $file = $tempdir->child('test.txt');
    $file->spew('test');

    my @children = $tempdir->children;
    my $item = DoubleDrive::FileListItem->new(path => $children[0]);

    is $item->format_name(10), 'test.txt  ', 'pads short name';
    is $item->format_name(8), 'test.txt', 'exact fit';
    is $item->format_name(5), 'te...', 'truncates long name';

    # Test directory with trailing slash
    my $dir_item = DoubleDrive::FileListItem->new(path => $tempdir);
    my $formatted = $dir_item->format_name(20);
    like $formatted, qr{/\s*$}, 'directory has trailing slash followed by padding';
};

subtest 'size' => sub {
    subtest 'returns file size from stat' => sub {
        # Create a mock stat object with size method
        my $stat_double = mock {} => (
            add => [
                size => sub { 1024 },
            ],
        );

        my $mock_path = mock 'Path::Tiny' => (
            override => [
                stat => sub { $stat_double },
                basename => sub { 'test.txt' },
                stringify => sub { '/fake/test.txt' },
            ],
        );

        my $item = DoubleDrive::FileListItem->new(path => path('/fake/test.txt'));
        is $item->size, 1024, 'returns file size from stat';
    };

    subtest 'returns 0 for missing file' => sub {
        # Test missing file (stat throws exception)
        my $missing = DoubleDrive::FileListItem->new(path => path('/fake/missing.txt'));
        is $missing->size, 0, 'returns 0 for missing file';
    };
};

subtest 'mtime' => sub {
    subtest 'returns modification time from stat' => sub {
        # Create a mock stat object with mtime method
        my $expected_mtime = 1_609_459_200;  # 2021-01-01
        my $stat_double = mock {} => (
            add => [
                mtime => sub { $expected_mtime },
            ],
        );

        my $mock_path = mock 'Path::Tiny' => (
            override => [
                stat => sub { $stat_double },
                basename => sub { 'test.txt' },
                stringify => sub { '/fake/test.txt' },
            ],
        );

        my $item = DoubleDrive::FileListItem->new(path => path('/fake/test.txt'));
        is $item->mtime, $expected_mtime, 'returns modification time from stat';
    };

    subtest 'returns 0 for missing file' => sub {
        # Test missing file (stat throws exception)
        my $missing = DoubleDrive::FileListItem->new(path => path('/fake/missing.txt'));
        is $missing->mtime, 0, 'returns 0 for missing file';
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

        # Mock Path::Tiny to return our test filename as basename
        my $mock_path = mock 'Path::Tiny' => (
            override => [
                basename => sub { $filename },
                stringify => sub { "/fake/path/$filename" },
            ],
        );

        my $item = DoubleDrive::FileListItem->new(path => path('/fake'));
        is $item->extname, $expected, $desc;
    }
};

done_testing;
