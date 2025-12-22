use v5.42;
use utf8;

use Test2::V0;
use POSIX qw(tzset);
use lib 't/lib';
use DoubleDrive::Test::Time qw(sub_at);
use DoubleDrive::Test::Mock qw(StubStat FIXED_MTIME mock_window mock_rb_and_rect);
use Path::Tiny qw(path tempdir);

use lib 'lib';
use DoubleDrive::FileListView;
use DoubleDrive::FileListItem;

BEGIN {
    $ENV{TZ} = 'UTC';
    tzset();
}

subtest '_max_name_width()' => sub {
    my $view = DoubleDrive::FileListView->new;

    # Formula: width - 2 (selector) - 8 (size) - 3 (spacing) - 11 (mtime) - 11 (mode) = width - 35
    is $view->_max_name_width(50), 15, 'normal width calculation';
    is $view->_max_name_width(35), 10, 'exactly minimum threshold';
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
    my $item = DoubleDrive::FileListItem->new(path => $file);
    my $rows = [{ item => $item, is_cursor => 0 }];

    my $lines = $view->_rows_to_lines($rows, 50);
    my $expected_text = '  test.txt       ';  # name width 15 at cols=50

    is $lines, [
        { text => $expected_text, pen => undef },
    ], 'single line with selector and padded name only';
};

subtest '_rows_to_lines() - formatted snapshot' => sub_at {
    my $view = DoubleDrive::FileListView->new;
    my $highlight_pen = DoubleDrive::FileListView::HIGHLIGHT_PEN;
    my $cursor_pen = DoubleDrive::FileListView::CURSOR_PEN;
    my $cursor_highlight_pen = DoubleDrive::FileListView::CURSOR_HIGHLIGHT_PEN;

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
                    ? StubStat(size => 4096, mtime => FIXED_MTIME, mode => 0755)
                    : StubStat(size => 1024, mtime => FIXED_MTIME, mode => 0644);
            },
        ],
    );

    my $plain     = DoubleDrive::FileListItem->new(path => path('/tmp/test.txt'));
    my $cursor    = DoubleDrive::FileListItem->new(path => path('/tmp/cursor.txt'));
    my $selected  = DoubleDrive::FileListItem->new(path => path('/tmp/selected.txt'));
    $selected->toggle_selected();
    my $match     = DoubleDrive::FileListItem->new(path => path('/tmp/match.txt'));
    $match->set_match(true);
    my $hit       = DoubleDrive::FileListItem->new(path => path('/tmp/hit.txt'));
    $hit->toggle_selected();
    $hit->set_match(true);
    my $long      = DoubleDrive::FileListItem->new(path => path('/tmp/this-is-a-very-long-filename.txt'));
    my $dir       = DoubleDrive::FileListItem->new(path => path('/tmp/mydir'));

    my $rows = [
        { item => $plain,    is_cursor => 0 },
        { item => $cursor,   is_cursor => 1 },
        { item => $selected, is_cursor => 0 },
        { item => $match,    is_cursor => 0 },
        { item => $hit,      is_cursor => 1 },
        { item => $long,     is_cursor => 0 },
        { item => $dir,      is_cursor => 0 },
    ];

    my $lines = $view->_rows_to_lines($rows, 50);
    is $lines, [
        { text => '  test.txt           1.0K  01/15 10:30 -rw-r--r--', pen => undef },
        { text => '> cursor.txt         1.0K  01/15 10:30 -rw-r--r--', pen => $cursor_pen },
        { text => ' *selected.txt       1.0K  01/15 10:30 -rw-r--r--', pen => undef },
        { text => '  match.txt          1.0K  01/15 10:30 -rw-r--r--', pen => $highlight_pen },
        { text => '>*hit.txt            1.0K  01/15 10:30 -rw-r--r--', pen => $cursor_highlight_pen },
        { text => '  this-is-a-ve...    1.0K  01/15 10:30 -rw-r--r--', pen => undef },
        { text => '  mydir/            <DIR>  01/15 10:30 drwxr-xr-x', pen => undef },
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
    my $item = DoubleDrive::FileListItem->new(path => $file);
    my $rows = [{ item => $item, is_cursor => 0 }];

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
    my $item = DoubleDrive::FileListItem->new(path => $file);
    my $rows = [{ item => $item, is_cursor => 0 }];

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

    my $tempdir = tempdir;
    my $dir = path($tempdir);
    my $file = $dir->child('test.txt');
    $file->spew('content');
    utime FIXED_MTIME, FIXED_MTIME, $file->stringify;  # Set mtime

    # Get file from children() to get real Path::Tiny behavior
    my @children = $dir->children;
    my $item = DoubleDrive::FileListItem->new(path => $children[0]);

    my $rows = [
        { item => $item, is_cursor => 1 },
    ];

    my $lines = $view->_rows_to_lines($rows, 60);

    is scalar(@$lines), 1, 'one line produced';
    like $lines->[0]{text}, qr/^> test\.txt/, 'formatted line starts with cursor';
    like $lines->[0]{text}, qr/01\/15 10:30/, 'contains formatted mtime';
    like $lines->[0]{text}, qr/\d+\.\d+[BKMGT]/, 'contains formatted size';
} '2025-01-15T10:30:00Z';

done_testing;
