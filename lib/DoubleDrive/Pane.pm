use v5.42;
use experimental 'class';

use Tickit::Widget::Frame;
use Tickit::Widget::Scroller;
use Tickit::Widget::Scroller::Item::Text;

class DoubleDrive::Pane {
    use Path::Tiny qw(path);

    field $current_path :param;
    field $files = [];
    field $widget :reader;
    field $scroller;

    ADJUST {
        $self->load_directory();
        $self->build_widget();
    }

    method load_directory() {
        my $dir = path($current_path);

        # Get all entries and sort alphabetically (case-insensitive)
        $files = [sort { fc($a->basename) cmp fc($b->basename) } $dir->children];
    }

    method build_widget() {
        $scroller = Tickit::Widget::Scroller->new();
        $self->update_display();

        $widget = Tickit::Widget::Frame->new(
            style => { linetype => "single" },
            title => $current_path->absolute->stringify,
        )->set_child($scroller);
    }

    method update_display() {
        for my $file (@$files) {
            my $name = $file->basename;
            $name .= "/" if $file->is_dir;

            $scroller->push(Tickit::Widget::Scroller::Item::Text->new($name));
        }
    }
}
