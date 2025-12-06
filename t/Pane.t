use v5.42;
use utf8;
use lib 'lib';

use Test2::V0;
use Test2::Tools::Mock qw(mock);

use Path::Tiny qw(path tempdir);
use Tickit;
use Tickit::Test qw(mk_term);

use DoubleDrive::FileListItem;

# Mock necessary modules
{
    package TestWidget;
    sub new($class, %args) { bless \%args, $class }
    sub set_title($self, $title) {
        $self->{title} = $title;
    }
    sub set_child($self, $child) {
        $self;
    }
}

{
    package TestFileListView;
    sub new($class, %args) { bless \%args, $class }
    sub window($self) { undef }
    sub set_rows($self, $rows) { }
}

# Load Pane module
use DoubleDrive::Pane;

sub setup_pane_mocks {
    my $widget = TestWidget->new;

    my $mock_frame = mock 'Tickit::Widget::Frame' => (
        override => [
            new => sub ($class, %args) {
                $widget->{title} = $args{title};
                $widget;
            },
        ],
    );
    my $mock_file_list_view = mock 'DoubleDrive::FileListView' => (
        override => [
            new => sub ($class, %args) {
                TestFileListView->new(%args);
            },
        ],
    );

    my $mocks = {
        frame => $mock_frame,
        file_list_view => $mock_file_list_view,
    };

    return ($mocks, $widget);
}

subtest '_format_path_title' => sub {
    my ($mocks, $widget) = setup_pane_mocks();
    my $home = path("~")->absolute->stringify;
    my $pane = DoubleDrive::Pane->new(path => path($home), on_status_change => sub { });

    is $pane->_format_path_title($home), "~", 'home directory';
    is $pane->_format_path_title("$home/Documents"), "~/Documents", 'subdirectory under home';
    is $pane->_format_path_title("$home/Documents/Projects/myproject"), "~/Documents/Projects/myproject", 'deeply nested path';
    is $pane->_format_path_title("/tmp"), "/tmp", '/tmp not modified';
    is $pane->_format_path_title("/usr/local"), "/usr/local", '/usr/local not modified';
    is $pane->_format_path_title("/"), "/", 'root not modified';
};

subtest 'widget title formatting' => sub {
    my ($mocks, $widget) = setup_pane_mocks();
    my $home = path("~")->absolute;
    my $pane = DoubleDrive::Pane->new(path => $home, on_status_change => sub { });

    is $widget->{title}, "~", 'initial title is ~';

    my $tmp = path("/tmp")->realpath;
    $pane->change_directory(DoubleDrive::FileListItem->new(path => $tmp));
    is $widget->{title}, $tmp->stringify, 'title updated for /tmp';

    $pane->change_directory(DoubleDrive::FileListItem->new(path => $home->realpath));
    is $widget->{title}, "~", 'title back to ~ for home';
};

subtest 'set_sort' => sub {
    my ($mocks, $widget) = setup_pane_mocks();

    # Create a temporary test directory with files
    my $tempdir = tempdir;

    # Create test files with different sizes and mtimes
    my $file_a = $tempdir->child('aaa.txt');
    my $file_b = $tempdir->child('bbb.md');
    my $file_c = $tempdir->child('ccc.txt');

    $file_a->spew("x" x 100);   # size: 100
    $file_b->spew("x" x 300);   # size: 300
    $file_c->spew("x" x 200);   # size: 200

    # Adjust mtimes by touching files in specific order
    sleep 1;
    $file_b->touch;  # most recent
    sleep 1;
    $file_a->touch;
    sleep 1;
    $file_c->touch;  # newest

    my $pane = DoubleDrive::Pane->new(
        path => $tempdir,
        on_status_change => sub { }
    );

    subtest 'default sort by name' => sub {
        my $files = $pane->files;
        is scalar(@$files), 3, 'has 3 files';
        is $files->[0]->basename, 'aaa.txt', 'first file is aaa.txt';
        is $files->[1]->basename, 'bbb.md', 'second file is bbb.md';
        is $files->[2]->basename, 'ccc.txt', 'third file is ccc.txt';
    };

    subtest 'sort by size' => sub {
        $pane->set_sort('size');
        my $files = $pane->files;
        is $files->[0]->basename, 'bbb.md', 'first file is bbb.md (size 300)';
        is $files->[1]->basename, 'ccc.txt', 'second file is ccc.txt (size 200)';
        is $files->[2]->basename, 'aaa.txt', 'third file is aaa.txt (size 100)';
    };

    subtest 'sort by mtime' => sub {
        $pane->set_sort('mtime');
        my $files = $pane->files;
        is $files->[0]->basename, 'ccc.txt', 'first file is ccc.txt (newest)';
        is $files->[1]->basename, 'aaa.txt', 'second file is aaa.txt';
        is $files->[2]->basename, 'bbb.md', 'third file is bbb.md (oldest)';
    };

    subtest 'sort by extension' => sub {
        $pane->set_sort('ext');
        my $files = $pane->files;
        # .md comes before .txt alphabetically
        is $files->[0]->basename, 'bbb.md', 'first file is bbb.md (.md)';
        # .txt files sorted by name
        is $files->[1]->basename, 'aaa.txt', 'second file is aaa.txt (.txt)';
        is $files->[2]->basename, 'ccc.txt', 'third file is ccc.txt (.txt)';
    };

    subtest 'cursor position maintained after sort' => sub {
        # Reset to name sort and select middle file
        $pane->set_sort('name');
        my $files = $pane->files;

        # Select bbb.md (index 1 in name sort)
        $pane->move_cursor(1);
        is $pane->selected_index, 1, 'cursor on index 1 (bbb.md)';
        is $files->[$pane->selected_index]->basename, 'bbb.md', 'selected file is bbb.md';

        # Sort by size (bbb.md should move to index 0)
        $pane->set_sort('size');
        $files = $pane->files;
        is $pane->selected_index, 0, 'cursor follows bbb.md to index 0';
        is $files->[$pane->selected_index]->basename, 'bbb.md', 'selected file is still bbb.md';
    };

    subtest 'no-op when sort key unchanged' => sub {
        # Set to size sort
        $pane->set_sort('size');
        my $files = $pane->files;
        my $selected_before = $pane->selected_index;

        # Try to set to size again
        $pane->set_sort('size');
        is $pane->selected_index, $selected_before, 'cursor position unchanged';
        is scalar(@{$pane->files}), scalar(@$files), 'files unchanged';
    };
};

done_testing;
