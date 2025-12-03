use v5.42;
use utf8;

use Test2::V0;
use POSIX qw(tzset);
use lib 't/lib';
use DoubleDrive::Test::Time qw(sub_at);
use DoubleDrive::Test::Mock qw(StubStat FIXED_MTIME mock_window mock_rb_and_rect);
use Path::Tiny qw(path);
use File::Temp qw(tempdir);

use lib 'lib';
use DoubleDrive::FileListView;

BEGIN {
    $ENV{TZ} = 'UTC';
    tzset();
}

subtest '_format_size()' => sub {
    my $view = DoubleDrive::FileListView->new;

    # One rep for each unit boundary (min of new unit and just-before)
    is $view->_format_size(0), '   0.0B', '0 bytes';
    is $view->_format_size(1023), '1023.0B', 'max bytes';
    is $view->_format_size(1024), '   1.0K', 'min KiB';
    is $view->_format_size(1_048_575), '1024.0K', 'max KiB';
    is $view->_format_size(1_048_576), '   1.0M', 'min MiB';
    is $view->_format_size(1_073_741_824), '   1.0G', 'min GiB';
    is $view->_format_size(1_099_511_627_776), '   1.0T', 'min TiB';
};

subtest '_format_mtime()' => sub_at {
    my $view = DoubleDrive::FileListView->new;

    # Within one year: show month/day and time
    is $view->_format_mtime(1_736_937_000), '01/15 10:30', 'current time (2025-01-15 10:30:00)';
    is $view->_format_mtime(1_705_401_001), '01/16 10:30', 'just within one year (1 second inside threshold)';

    # Older than one year: show date only
    is $view->_format_mtime(1_705_400_999), '2024-01-16', 'just over one year ago';
    is $view->_format_mtime(1_609_459_200), '2021-01-01', '~4 years ago';
} '2025-01-15T10:30:00Z';

subtest '_format_name()' => sub {
    my $view = DoubleDrive::FileListView->new;

    # Padding / exact fit
    is $view->_format_name('abc', 3), 'abc', 'exact fit no padding';
    is $view->_format_name('abc', 10), 'abc       ', 'short name padded';
    is $view->_format_name('', 5), '     ', 'empty string padded';

    # Truncation when width is insufficient
    is $view->_format_name('very-long-file-name.txt', 12), 'very-long...', 'long name truncated';
    is $view->_format_name('test', 3), '...', 'target width equals ellipsis';

    # Extremely narrow widths collapse to ellipsis
    is $view->_format_name('hello', 2), '...', 'target width 2 (less than ellipsis)';

    # Wide characters (e.g., Japanese) - 2 columns per char
    my $wide = "あいう";  # 3 chars, 6 columns wide
    is $view->_format_name($wide, 6), "あいう", 'wide chars exact fit';
    is $view->_format_name($wide, 5), "あ...", 'wide chars truncated';

    # Combining characters - 0 width
    my $combining = "e\N{COMBINING ACUTE ACCENT}e";  # 3 chars, 2 columns
    is $view->_format_name($combining, 2), "e\N{COMBINING ACUTE ACCENT}e", 'combining chars exact fit';
    is $view->_format_name($combining, 4), "e\N{COMBINING ACUTE ACCENT}e  ", 'combining chars padded safely';
};

subtest '_max_name_width()' => sub {
    my $view = DoubleDrive::FileListView->new;

    # Formula: width - 2 (selector) - 8 (size) - 3 (spacing) - 11 (mtime) = width - 24
    is $view->_max_name_width(50), 26, 'normal width calculation';
    is $view->_max_name_width(24), 10, 'exactly minimum threshold';
    is $view->_max_name_width(10), 10, 'below minimum enforces floor';
};

subtest '_rows_to_lines() - empty directory' => sub {
    my $view = DoubleDrive::FileListView->new;

    my $lines = $view->_rows_to_lines([], undef);
    is $lines, [{ text => "(empty directory)" }], 'empty directory message';
};

subtest '_rows_to_lines() - file without stat' => sub {
    my $view = DoubleDrive::FileListView->new;

    my $mock_file = mock 'Path::Tiny' => (
        override => [
            basename => sub { 'test.txt' },
            is_dir => sub { 0 },
            stat => sub { undef },  # stat fails
        ],
    );

    my $file = path('/tmp/test.txt');
    my $rows = [{ path => $file, is_cursor => 0, is_selected => 0, is_match => 0 }];

    my $lines = $view->_rows_to_lines($rows, 50);
    my $expected_text = '  test.txt                  ';  # name width 26 at cols=50

    is $lines, [
        { text => $expected_text, pen => undef },
    ], 'single line with selector and padded name only';
};

subtest '_rows_to_lines() - formatted snapshot' => sub_at {
    my $view = DoubleDrive::FileListView->new;
    my $highlight_pen = DoubleDrive::FileListView::HIGHLIGHT_PEN;

    my $mock_file = mock 'Path::Tiny' => (
        override => [
            basename => sub {
                my $self = shift;
                my $str = "$self";
                return $str =~ s{.*/}{}r;
            },
            is_dir => sub {
                my $self = shift;
                return "$self" =~ m{/mydir$} ? 1 : 0;
            },
            stat => sub {
                my $self = shift;
                return "$self" =~ m{/mydir$}
                    ? StubStat(size => 4096, mtime => FIXED_MTIME)
                    : StubStat(size => 1024, mtime => FIXED_MTIME);
            },
        ],
    );

    my $plain     = path('/tmp/test.txt');
    my $cursor    = path('/tmp/cursor.txt');
    my $selected  = path('/tmp/selected.txt');
    my $match     = path('/tmp/match.txt');
    my $hit       = path('/tmp/hit.txt');
    my $long      = path('/tmp/this-is-a-very-long-filename.txt');
    my $dir       = path('/tmp/mydir');

    my $rows = [
        { path => $plain,    is_cursor => 0, is_selected => 0, is_match => 0 },
        { path => $cursor,   is_cursor => 1, is_selected => 0, is_match => 0 },
        { path => $selected, is_cursor => 0, is_selected => 1, is_match => 0 },
        { path => $match,    is_cursor => 0, is_selected => 0, is_match => 1 },
        { path => $hit,      is_cursor => 1, is_selected => 1, is_match => 1 },
        { path => $long,     is_cursor => 0, is_selected => 0, is_match => 0 },
        { path => $dir,      is_cursor => 0, is_selected => 0, is_match => 0 },
    ];

    my $lines = $view->_rows_to_lines($rows, 50);
    is $lines, [
        { text => '  test.txt                      1.0K  01/15 10:30', pen => undef },
        { text => '> cursor.txt                    1.0K  01/15 10:30', pen => undef },
        { text => ' *selected.txt                  1.0K  01/15 10:30', pen => undef },
        { text => '  match.txt                     1.0K  01/15 10:30', pen => $highlight_pen },
        { text => '>*hit.txt                       1.0K  01/15 10:30', pen => $highlight_pen },
        { text => '  this-is-a-very-long-fil...    1.0K  01/15 10:30', pen => undef },
        { text => '  mydir/                        4.0K  01/15 10:30', pen => undef },
    ], 'selector markers, highlight pen, and dir slash in one snapshot';
} '2025-01-15T10:30:00Z';

subtest 'set_rows() - updates internal lines' => sub {
    my $view = DoubleDrive::FileListView->new;

    my $mock_file = mock 'Path::Tiny' => (
        override => [
            basename => sub { 'test.txt' },
            is_dir => sub { 0 },
            stat => sub { StubStat(size => 1024, mtime => FIXED_MTIME) },
        ],
    );

    my $window = mock_window(80);

    my $view_mock = mock 'DoubleDrive::FileListView' => (
        override => [
            window => sub { $window },
            redraw => sub { },  # No-op for testing
        ],
    );

    my $file = path('/tmp/test.txt');
    my $rows = [{ path => $file, is_cursor => 0, is_selected => 0, is_match => 0 }];

    $view->set_rows($rows);

    is scalar(@{$view->{lines}}), 1, 'lines array updated';
    like $view->{lines}[0]{text}, qr/test\.txt/, 'line contains filename';
};

subtest 'set_rows() - without window (no redraw)' => sub {
    my $view = DoubleDrive::FileListView->new;

    my $mock_file = mock 'Path::Tiny' => (
        override => [
            basename => sub { 'test.txt' },
            is_dir => sub { 0 },
            stat => sub { StubStat(size => 1024, mtime => FIXED_MTIME) },
        ],
    );

    my $file = path('/tmp/test.txt');
    my $rows = [{ path => $file, is_cursor => 0, is_selected => 0, is_match => 0 }];

    # No window attached - should not crash
    my $result = $view->set_rows($rows);
    is $result, $view, 'returns self';
    is scalar(@{$view->{lines}}), 1, 'lines array still updated';
};

subtest 'render_to_rb()' => sub {
    my $view = DoubleDrive::FileListView->new;

    # Full coverage when lines fill the rect
    $view->{lines} = [
        { text => "line 0", pen => undef },
        { text => "line 1", pen => undef },
        { text => "line 2", pen => undef },
    ];
    my ($rb, $rect, $rendered) = mock_rb_and_rect(0, 3);
    $view->render_to_rb($rb, $rect);
    is $rendered, [
        { line => 0, col => 0, text => 'line 0', pen => undef },
        { line => 1, col => 0, text => 'line 1', pen => undef },
        { line => 2, col => 0, text => 'line 2', pen => undef },
    ], 'rendered all three lines';

    # Partial render range clips to rect and preserves pen
    my $highlight = DoubleDrive::FileListView::HIGHLIGHT_PEN;
    $view->{lines} = [
        { text => "line 0", pen => undef },
        { text => "hit",    pen => $highlight },
        { text => "line 2", pen => undef },
        { text => "line 3", pen => undef },
        { text => "line 4", pen => undef },
    ];
    ($rb, $rect, $rendered) = mock_rb_and_rect(1, 4);
    $view->render_to_rb($rb, $rect);
    is $rendered, [
        { line => 1, col => 0, text => 'hit',    pen => $highlight },
        { line => 2, col => 0, text => 'line 2', pen => undef },
        { line => 3, col => 0, text => 'line 3', pen => undef },
    ], 'rendered only lines 1-3 for rect top=1 bottom=4 with pen preserved';

    # Empty lines produce no output
    $view->{lines} = [];
    ($rb, $rect, $rendered) = mock_rb_and_rect(0, 5);
    $view->render_to_rb($rb, $rect);
    is scalar(@$rendered), 0, 'no lines rendered when empty';

    # Render area larger than lines stops at available lines
    $view->{lines} = [
        { text => "line 0", pen => undef },
        { text => "line 1", pen => undef },
    ];
    ($rb, $rect, $rendered) = mock_rb_and_rect(0, 10);
    $view->render_to_rb($rb, $rect);
    is $rendered, [
        { line => 0, col => 0, text => 'line 0', pen => undef },
        { line => 1, col => 0, text => 'line 1', pen => undef },
    ], 'rendered only available lines';
};

subtest 'integration - complete formatting flow' => sub_at {
    my $view = DoubleDrive::FileListView->new;

    my $tempdir = tempdir(CLEANUP => 1);
    my $file = path($tempdir, 'test.txt');
    $file->spew('content');
    utime FIXED_MTIME, FIXED_MTIME, $file->stringify;  # Set mtime

    my $rows = [
        { path => $file, is_cursor => 1, is_selected => 0, is_match => 0 },
    ];

    my $lines = $view->_rows_to_lines($rows, 60);

    is scalar(@$lines), 1, 'one line produced';
    like $lines->[0]{text}, qr/^> test\.txt/, 'formatted line starts with cursor';
    like $lines->[0]{text}, qr/01\/15 10:30/, 'contains formatted mtime';
    like $lines->[0]{text}, qr/\d+\.\d+[BKMGT]/, 'contains formatted size';
} '2025-01-15T10:30:00Z';

done_testing;
