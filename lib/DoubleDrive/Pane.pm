use v5.42;
use experimental 'class';

use Tickit::Widget::Frame;
use Tickit::Widget::Scroller;
use Tickit::Widget::Scroller::Item::Text;

class DoubleDrive::Pane {
    use Path::Tiny qw(path);

    field $path :param;          # Initial path (string or Path::Tiny object) passed to constructor
    field $current_path;         # Current directory as Path::Tiny object
    field $files = [];
    field $selected_index = 0;
    field $widget :reader;
    field $scroller;
    field $is_active = false;

    ADJUST {
        $current_path = path($path);
        $self->_build_widget();
        $self->_load_directory();
    }

    method _build_widget() {
        $scroller = Tickit::Widget::Scroller->new();

        $widget = Tickit::Widget::Frame->new(
            style => { linetype => "single" },
            title => $current_path->absolute->stringify,
        )->set_child($scroller);
    }

    method _load_directory() {
        # Get all entries and sort alphabetically (case-insensitive)
        $files = [sort { fc($a->basename) cmp fc($b->basename) } $current_path->children];
        $self->_render();
    }

    method _render() {
        # Recreate scroller with current files and selection
        $scroller = Tickit::Widget::Scroller->new();

        for my ($index, $file) (indexed @$files) {
            my $name = $file->basename;
            $name .= "/" if $file->is_dir;

            my $selected = ($index == $selected_index) ? "> " : "  ";
            my $line = $selected . $name;

            $scroller->push(Tickit::Widget::Scroller::Item::Text->new($line));
        }

        $widget->set_child($scroller);
    }

    method move_selection($delta) {
        my $new_index = $selected_index + $delta;

        if ($new_index >= 0 && $new_index < scalar(@$files)) {
            $selected_index = $new_index;
            $self->_render();
        }
    }

    method change_directory($new_path) {
        $current_path = $new_path;
        $selected_index = 0;
        $widget->set_title($current_path->absolute->stringify);
        $self->_load_directory();
    }

    method enter_selected() {
        return unless @$files > 0;

        my $selected = $files->[$selected_index];
        if ($selected->is_dir) {
            $self->change_directory($selected);
        }
    }

    method set_active($active) {
        $is_active = $active;
        $widget->set_style(linetype => $is_active ? "double" : "single");
    }
}
