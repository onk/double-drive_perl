use v5.42;

use Test2::V0;
use File::Temp qw(tempdir);
use POSIX qw(tzset);
use lib 't/lib';
use DoubleDrive::Test::Time qw(sub_at);

use lib 'lib';
use DoubleDrive::Pane;

BEGIN {
    $ENV{TZ} = 'UTC';
    tzset();
}

subtest 'size formatter' => sub {
    my $pane = DoubleDrive::Pane->new(path => tempdir(CLEANUP => 1));

    is $pane->_format_size(1023), '1023.0B', 'bytes stay in B';
    is $pane->_format_size(1024), '   1.0K', '1 KiB rounds';
    is $pane->_format_size(1048576), '   1.0M', '1 MiB rounds';
};

subtest 'mtime formatter' => sub_at {
    my $pane = DoubleDrive::Pane->new(path => tempdir(CLEANUP => 1));

    is $pane->_format_mtime(1_599_999_000), '09/13 12:10', 'within a year shows month/day';
    is $pane->_format_mtime(1_500_000_000), '2017-07-14', 'older than a year shows date';
} '2020-09-13T12:10:00Z';

subtest 'name formatter width handling' => sub {
    my $pane = DoubleDrive::Pane->new(path => tempdir(CLEANUP => 1));

    my $short = $pane->_format_name('abc', 10);
    is $short, 'abc       ', 'short name padded with spaces';

    my $long = $pane->_format_name('very-long-file-name.txt', 12);
    is $long, 'very-long...', 'long name truncated with ellipsis';

    my $combining = "e\N{COMBINING ACUTE ACCENT}e"; # width 2 visually
    my $formatted = $pane->_format_name($combining, 4);
    is $formatted, "e\N{COMBINING ACUTE ACCENT}e  ", 'combining characters padded safely';
};

done_testing;
