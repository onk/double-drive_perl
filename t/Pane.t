use v5.42;
use utf8;
use lib 'lib';

use Test2::V0;
use Test2::Tools::Mock qw(mock);

use Path::Tiny;
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

done_testing;
