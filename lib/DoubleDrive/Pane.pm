use v5.42;
use experimental 'class';

use Tickit::Widget::Frame;
use DoubleDrive::TextWidget;

class DoubleDrive::Pane {
    use Path::Tiny qw(path);
    use List::Util qw(min);

    field $path :param;          # Initial path (string or Path::Tiny object) passed to constructor
    field $current_path;         # Current directory as Path::Tiny object
    field $files = [];
    field $selected_index = 0;
    field $scroll_offset = 0;    # First visible item index
    field $widget :reader;
    field $text_widget;
    field $is_active = false;

    ADJUST {
        $current_path = path($path);
        $self->_build_widget();
        $self->_load_directory();
    }

    method _build_widget() {
        $text_widget = DoubleDrive::TextWidget->new(text => "");

        $widget = Tickit::Widget::Frame->new(
            style => { linetype => "single" },
            title => $current_path->absolute->stringify,
        )->set_child($text_widget);
    }

    method _load_directory() {
        # Get all entries and sort alphabetically (case-insensitive)
        $files = [sort { fc($a->basename) cmp fc($b->basename) } $current_path->children];

        # Add parent directory at the beginning (unless we're at root)
        unshift @$files, $current_path->parent if $current_path->parent ne $current_path;

        $self->_render();
    }

    method after_window_attached() {
        $self->_render();
    }

    method _render() {
        # Skip rendering if not attached to window yet
        my $window = $text_widget->window;
        return unless $window;

        my $height = $window->lines;

        # Adjust scroll offset to keep selected item visible
        if ($selected_index < $scroll_offset) {
            # Selected item is above visible area
            $scroll_offset = $selected_index;
        } elsif ($selected_index >= $scroll_offset + $height) {
            # Selected item is below visible area
            $scroll_offset = $selected_index - $height + 1;
        }

        # Build visible content
        my $content_lines = [];
        my $end_index = min($scroll_offset + $height - 1, $#$files);

        for my $index ($scroll_offset .. $end_index) {
            my $file = $files->[$index];
            my $name = $file->basename;
            $name = ".." if $file eq $current_path->parent;
            $name .= "/" if $file->is_dir;

            my $selected = ($index == $selected_index) ? "> " : "  ";
            push @$content_lines, $selected . $name;
        }

        $text_widget->set_text(join("\n", @$content_lines));
    }

    method move_selection($delta) {
        my $new_index = $selected_index + $delta;

        if ($new_index >= 0 && $new_index < scalar(@$files)) {
            $selected_index = $new_index;
            $self->_render();
        }
    }

    method change_directory($new_path) {
        # Handle both string paths and Path::Tiny objects
        my $path_obj = $new_path isa Path::Tiny
            ? $new_path
            : path($current_path, $new_path);
        $current_path = $path_obj->realpath;
        $selected_index = 0;
        $scroll_offset = 0;
        $widget->set_title($current_path->stringify);
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
