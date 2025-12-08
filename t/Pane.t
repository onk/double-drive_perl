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

# Fake stat object for testing without sleep
{
    package Test::FakeStat;
    sub size($self) { $self->{size} }
    sub mtime($self) { $self->{mtime} }
}

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

    # Mock stat to control mtime without sleep
    my $mtime_overrides = {
        $file_b->realpath->stringify => 1000,  # oldest
        $file_a->realpath->stringify => 2000,
        $file_c->realpath->stringify => 3000,  # newest
    };

    my $mock_item = mock 'DoubleDrive::FileListItem' => (
        override => [
            stat => sub ($self) {
                my $real_stat = $self->path->stat;
                my $path_str = $self->stringify;  # Use FileListItem's stringify, not Path::Tiny's
                # diag "stat called for: $path_str";
                # diag "  exists in overrides: " . (exists $mtime_overrides->{$path_str} ? "yes" : "no");
                if (exists $mtime_overrides->{$path_str}) {
                    # diag "  returning fake mtime: " . $mtime_overrides->{$path_str};
                    return bless {
                        size => $real_stat->size,
                        mtime => $mtime_overrides->{$path_str},
                    }, 'Test::FakeStat';
                }
                return $real_stat;
            },
        ],
    );

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

subtest 'directories sorted before files' => sub {
    my ($mocks, $widget) = setup_pane_mocks();

    # Create a temporary test directory with both files and directories
    my $tempdir = tempdir;

    # Create files and directories with names that would interleave if sorted purely alphabetically
    my $dir_b = $tempdir->child('bbb_dir');
    my $dir_d = $tempdir->child('ddd_dir');
    $dir_b->mkpath;
    $dir_d->mkpath;

    my $file_a = $tempdir->child('aaa.txt');
    my $file_c = $tempdir->child('ccc.txt');
    my $file_e = $tempdir->child('eee.txt');

    $file_a->spew("x" x 300);   # largest file
    $file_c->spew("x" x 200);
    $file_e->spew("x" x 100);   # smallest file

    # Mock stat to control mtime without sleep
    my $mtime_overrides = {
        $file_c->realpath->stringify => 1000,  # oldest file
        $file_a->realpath->stringify => 2000,
        $file_e->realpath->stringify => 3000,  # newest file
    };

    my $mock_item = mock 'DoubleDrive::FileListItem' => (
        override => [
            stat => sub ($self) {
                my $real_stat = $self->path->stat;
                my $path_str = $self->stringify;  # Use FileListItem's stringify, not Path::Tiny's
                if (exists $mtime_overrides->{$path_str}) {
                    return bless {
                        size => $real_stat->size,
                        mtime => $mtime_overrides->{$path_str},
                    }, 'Test::FakeStat';
                }
                return $real_stat;
            },
        ],
    );

    my $pane = DoubleDrive::Pane->new(
        path => $tempdir,
        on_status_change => sub { }
    );

    subtest 'sort by name: directories first' => sub {
        $pane->set_sort('name');
        my $files = $pane->files;

        is scalar(@$files), 5, 'has 5 items';

        # Directories should come first (bbb_dir, ddd_dir)
        ok $files->[0]->is_dir, 'first item is a directory';
        is $files->[0]->basename, 'bbb_dir', 'first directory is bbb_dir';

        ok $files->[1]->is_dir, 'second item is a directory';
        is $files->[1]->basename, 'ddd_dir', 'second directory is ddd_dir';

        # Then files (aaa.txt, ccc.txt, eee.txt)
        ok !$files->[2]->is_dir, 'third item is a file';
        is $files->[2]->basename, 'aaa.txt', 'first file is aaa.txt';

        ok !$files->[3]->is_dir, 'fourth item is a file';
        is $files->[3]->basename, 'ccc.txt', 'second file is ccc.txt';

        ok !$files->[4]->is_dir, 'fifth item is a file';
        is $files->[4]->basename, 'eee.txt', 'third file is eee.txt';
    };

    subtest 'sort by size: directories first' => sub {
        $pane->set_sort('size');
        my $files = $pane->files;

        # Directories first (sorted by name: bbb_dir, ddd_dir)
        ok $files->[0]->is_dir, 'first item is a directory';
        is $files->[0]->basename, 'bbb_dir', 'first directory is bbb_dir';

        ok $files->[1]->is_dir, 'second item is a directory';
        is $files->[1]->basename, 'ddd_dir', 'second directory is ddd_dir';

        # Then files by size: aaa.txt (300), ccc.txt (200), eee.txt (100)
        ok !$files->[2]->is_dir, 'third item is a file';
        is $files->[2]->basename, 'aaa.txt', 'largest file is aaa.txt';

        ok !$files->[3]->is_dir, 'fourth item is a file';
        is $files->[3]->basename, 'ccc.txt', 'second largest file is ccc.txt';

        ok !$files->[4]->is_dir, 'fifth item is a file';
        is $files->[4]->basename, 'eee.txt', 'smallest file is eee.txt';
    };

    subtest 'sort by mtime: directories first' => sub {
        $pane->set_sort('mtime');
        my $files = $pane->files;

        # Directories first (sorted by name: bbb_dir, ddd_dir)
        ok $files->[0]->is_dir, 'first item is a directory';
        is $files->[0]->basename, 'bbb_dir', 'first directory is bbb_dir';

        ok $files->[1]->is_dir, 'second item is a directory';
        is $files->[1]->basename, 'ddd_dir', 'second directory is ddd_dir';

        # Then files by mtime: eee.txt (newest), aaa.txt, ccc.txt (oldest)
        ok !$files->[2]->is_dir, 'third item is a file';
        is $files->[2]->basename, 'eee.txt', 'newest file is eee.txt';

        ok !$files->[3]->is_dir, 'fourth item is a file';
        is $files->[3]->basename, 'aaa.txt', 'second newest file is aaa.txt';

        ok !$files->[4]->is_dir, 'fifth item is a file';
        is $files->[4]->basename, 'ccc.txt', 'oldest file is ccc.txt';
    };

    subtest 'sort by ext: directories first' => sub {
        $pane->set_sort('ext');
        my $files = $pane->files;

        # Directories first (sorted by name: bbb_dir, ddd_dir)
        ok $files->[0]->is_dir, 'first item is a directory';
        is $files->[0]->basename, 'bbb_dir', 'first directory is bbb_dir';

        ok $files->[1]->is_dir, 'second item is a directory';
        is $files->[1]->basename, 'ddd_dir', 'second directory is ddd_dir';

        # Then files by extension and name (all .txt, sorted by name)
        ok !$files->[2]->is_dir, 'third item is a file';
        is $files->[2]->basename, 'aaa.txt', 'first .txt file is aaa.txt';

        ok !$files->[3]->is_dir, 'fourth item is a file';
        is $files->[3]->basename, 'ccc.txt', 'second .txt file is ccc.txt';

        ok !$files->[4]->is_dir, 'fifth item is a file';
        is $files->[4]->basename, 'eee.txt', 'third .txt file is eee.txt';
    };
};

done_testing;
