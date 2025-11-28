use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Pane {
    use Tickit::Widget::Frame;
    use DoubleDrive::TextWidget;
    use Path::Tiny qw(path);
    use List::Util qw(min);
    use POSIX qw(strftime);
    use Encode qw(decode_utf8);
    use Unicode::Normalize qw(NFC);
    use Unicode::GCString;

    field $path :param;              # Initial path (string or Path::Tiny object) passed to constructor
    field $on_status_change :param;
    field $is_active :param :reader = false;  # :reader for testing
    field $current_path :reader;     # Current directory as Path::Tiny object (:reader for testing)
    field $files = [];
    field $selected_index :reader = 0;  # :reader for testing
    field $scroll_offset = 0;        # First visible item index
    field $selected_files = {};      # Hash of selected file paths (stringified path as key)
    field $widget :reader;
    field $text_widget;

    ADJUST {
        $current_path = path($path);
        $self->_build_widget();
        $self->_load_directory();
    }

    method _build_widget() {
        $text_widget = DoubleDrive::TextWidget->new(text => "");

        $widget = Tickit::Widget::Frame->new(
            style => { linetype => "single" },
            title => NFC($current_path->absolute->stringify),
        )->set_child($text_widget);
    }

    method _load_directory() {
        # Get all entries and sort alphabetically (case-insensitive)
        $files = [sort { fc($a->basename) cmp fc($b->basename) } $current_path->children];

        # Add parent directory at the beginning (unless we're at root)
        unshift @$files, $current_path->parent if $current_path->parent ne $current_path;

        # Clear selection when loading a new directory
        $selected_files = {};

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
        my $width = $window->cols;

        # Calculate max name width (width - selection(2) - size(8) - spacing(3) - mtime(11))
        my $max_name_width = $width - 2 - 8 - 3 - 11;
        $max_name_width = 10 if $max_name_width < 10;  # Minimum width

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
            my $name = decode_utf8($file->basename);
            # macOS yields NFD names; normalize to NFC so Tickit width accounting stays aligned
            $name = NFC($name);
            $name = ".." if $file eq $current_path->parent;
            $name .= "/" if $file->is_dir;

            my $is_selected_file = exists $selected_files->{$file->stringify};
            my $is_cursor = ($index == $selected_index);
            my $selected = $is_selected_file
                ? ($is_cursor ? ">*" : " *")
                : ($is_cursor ? "> " : "  ");

            # Get file stats
            my $stat = $file->stat;
            if ($stat) {
                my $size = $self->_format_size($stat->size);
                my $mtime = $self->_format_mtime($stat->mtime);
                my $formatted_name = $self->_format_name($name, $max_name_width);
                push @$content_lines, $selected . $formatted_name . " " . $size . "  " . $mtime;
            } else {
                my $formatted_name = $self->_format_name($name, $max_name_width);
                push @$content_lines, $selected . $formatted_name;
            }
        }

        $text_widget->set_text(join("\n", @$content_lines));
    }

    method _format_size($bytes) {
        my $units = [qw(B K M G T)];
        my $unit_index = 0;
        my $size = $bytes;

        while ($size >= 1024 && $unit_index < $#$units) {
            $size /= 1024;
            $unit_index++;
        }

        return sprintf("%6.1f%s", $size, $units->[$unit_index]);
    }

    method _format_mtime($mtime) {
        my $one_year_ago = time() - (365 * 24 * 60 * 60);

        if ($mtime > $one_year_ago) {
            return strftime("%m/%d %H:%M", localtime($mtime));
        } else {
            return strftime("%Y-%m-%d", localtime($mtime));
        }
    }

    method _format_name($str, $target_width) {
        my $gc = Unicode::GCString->new($str);
        my $str_width = $gc->columns;

        if ($str_width <= $target_width) {
            return $str . (' ' x ($target_width - $str_width));
        }

        my $ellipsis = "...";
        my $ellipsis_width = 3;
        my $truncate_limit = $target_width - $ellipsis_width;
        return $ellipsis if $truncate_limit <= 0;

        my $out = "";
        my $used_width = 0;
        for my $g ($str =~ /\X/g) {
            my $w = Unicode::GCString->new($g)->columns;
            last if $used_width + $w > $truncate_limit;
            $out .= $g;
            $used_width += $w;
        }

        my $padding = $target_width - ($used_width + $ellipsis_width);
        $padding = 0 if $padding < 0;
        return $out . $ellipsis . (' ' x $padding);
    }

    method move_selection($delta) {
        my $new_index = $selected_index + $delta;

        if ($new_index >= 0 && $new_index < scalar(@$files)) {
            $selected_index = $new_index;
            $self->_render();
            $self->_notify_status_change();
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
        $widget->set_title(NFC($current_path->stringify));
        $self->_load_directory();
        $self->_notify_status_change();
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
        $self->_notify_status_change();
    }

    method _status_text() {
        my $selected = $files->[$selected_index];
        my $name = decode_utf8($selected->basename);
        $name = NFC($name);
        $name = ".." if $selected eq $current_path->parent;
        $name .= "/" if $selected->is_dir;

        my $total_files = scalar(@$files);
        my $position = $selected_index + 1;
        my $selected_count = scalar(keys %$selected_files);

        if ($selected_count > 0) {
            return sprintf("[%d/%d] (%d selected) %s", $position, $total_files, $selected_count, $name);
        } else {
            return sprintf("[%d/%d] %s", $position, $total_files, $name);
        }
    }

    method _notify_status_change() {
        return unless $is_active;
        my $status_text = $self->_status_text();
        $on_status_change->($status_text);
    }

    method toggle_selection() {
        my $file = $files->[$selected_index];
        my $key = $file->stringify;

        if (exists $selected_files->{$key}) {
            delete $selected_files->{$key};
        } else {
            $selected_files->{$key} = 1;
        }

        # Render to show selection change
        $self->_render();

        # Move cursor down after toggling selection for easy multi-selection
        $self->move_selection(1);
    }

    method get_files_to_operate() {
        # Return selected files if any exist, otherwise return current file
        if (keys %$selected_files) {
            return [grep { exists $selected_files->{$_->stringify} } @$files];
        } else {
            return [$files->[$selected_index]];
        }
    }

    method reload_directory() {
        # Remember the file the cursor was on
        my $current_file = $files->[$selected_index];
        my $current_file_path = $current_file->stringify;

        $self->_load_directory();

        # Try to find the same file in the reloaded list
        my $new_index;
        for my ($i, $file) (indexed @$files) {
            if ($file->stringify eq $current_file_path) {
                $new_index = $i;
                last;
            }
        }

        # If file not found (was deleted), keep similar position
        if (!defined $new_index) {
            $new_index = $selected_index;
            $new_index = $#$files if $new_index > $#$files;
        }

        $selected_index = $new_index;
        $self->_render();
        $self->_notify_status_change();
    }
}
