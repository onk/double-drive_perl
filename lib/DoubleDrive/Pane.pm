use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Pane {
    use Tickit::Widget::Frame;
    use Tickit::Pen;
    use DoubleDrive::FileListView;
    use DoubleDrive::FileListItem;
    use Path::Tiny qw(path);
    use List::Util qw(min first);
    use List::MoreUtils qw(firstidx);

    field $path :param;              # Initial path (string or Path::Tiny object) passed to constructor
    field $on_status_change :param;
    field $is_active :param :reader = false;  # :reader for testing
    field $current_path :reader;     # Current directory as FileListItem object (:reader for testing)
    field $files :reader = [];       # Array of FileListItem objects (:reader for testing)
    field $selected_index :reader = 0;  # :reader for testing
    field $scroll_offset = 0;        # First visible item index
    field $widget :reader;
    field $file_list_view;

    # Search state
    field $last_search_query = "";
    field $last_match_pos;                # Last position in match list (1-indexed)

    ADJUST {
        $current_path = DoubleDrive::FileListItem->new(path => path($path)->realpath);
        $self->_build_widget();
        $self->_load_directory();
        $self->_render();
    }

    method _build_widget() {
        $file_list_view = DoubleDrive::FileListView->new(text => "");

        $widget = Tickit::Widget::Frame->new(
            style => { linetype => "single" },
            title => $current_path->stringify,
        )->set_child($file_list_view);
    }

    method _load_directory() {
        # Get all entries as FileListItem, and sort by NFC normalized basename
        $files = [sort { fc($a->basename) cmp fc($b->basename) } @{$current_path->children}];
    }

    method after_window_attached() {
        $self->set_active($is_active);
        $self->_render();
    }

    method _render_file_list() {
        # Skip rendering if not attached to window yet
        my $window = $file_list_view->window;
        return unless $window;

        if (!@$files) {
            $file_list_view->set_rows([]);
            return;
        }

        my $height = $window->lines;

        # Adjust scroll offset to keep selected item visible
        if ($selected_index < $scroll_offset) {
            # Selected item is above visible area
            $scroll_offset = $selected_index;
        } elsif ($selected_index >= $scroll_offset + $height) {
            # Selected item is below visible area
            $scroll_offset = $selected_index - $height + 1;
        }

        # Build display lines with color highlighting for search matches
        my $rows = [];
        my $end_index = min($scroll_offset + $height - 1, $#$files);

        for my $index ($scroll_offset .. $end_index) {
            my $item = $files->[$index];

            my $is_cursor = ($is_active && $index == $selected_index);
            push @$rows, {
                item      => $item,
                is_cursor => $is_cursor,
            };
        }

        $file_list_view->set_rows($rows);
    }

    method _render() {
        $self->_render_file_list();
        $self->_render_status_bar();
    }

    method move_cursor($delta) {
        return unless @$files;

        my $new_index = $selected_index + $delta;

        if ($new_index >= 0 && $new_index < scalar(@$files)) {
            $selected_index = $new_index;
            $self->_render();
        }
    }

    method move_cursor_top() {
        $self->move_cursor(-$selected_index);
    }
    method move_cursor_bottom() {
        $self->move_cursor($#$files - $selected_index);
    }

    method change_directory($new_path) {
        my $previous_path = $current_path;

        # Handle FileListItem and string paths
        if ($new_path isa DoubleDrive::FileListItem) {
            $current_path = $new_path->realpath;
        } else {
            my $path_obj = path($current_path->path, $new_path);
            $current_path = DoubleDrive::FileListItem->new(path => $path_obj->realpath);
        }
        $selected_index = 0;
        $scroll_offset = 0;
        $widget->set_title($current_path->stringify);

        # Clear search state when changing directories
        # Note: We don't call clear_search() here to avoid double rendering.
        # _load_directory() creates new FileListItem objects, so is_match flags
        # will be reset automatically.
        $last_search_query = "";
        $last_match_pos = undef;

        $self->_load_directory();

        # When explicitly moving to parent (".."), select the directory we came from if it exists
        if (!($new_path isa DoubleDrive::FileListItem) && $new_path eq "..") {
            if (@$files) {
                my $new_index;
                for my ($i, $item) (indexed @$files) {
                    if ($item->stringify eq $previous_path->stringify) {
                        $new_index = $i;
                        last;
                    }
                }
                if (defined $new_index) {
                    $selected_index = $new_index;
                }
            }
        }

        $self->_render();
    }

    method enter_selected() {
        return unless @$files;
        my $selected = $files->[$selected_index];
        if ($selected->is_dir) {
            $self->change_directory($selected);
        }
    }

    method set_active($active) {
        $is_active = $active;
        $widget->set_style(linetype => $is_active ? "double" : "single");
        $self->_render();
    }

    method _status_text() {
        my $total_files = scalar(@$files);
        my $base_status = $total_files == 0 ? "[0/0]" : do {
            my $selected = $files->[$selected_index];
            my $name = $selected->basename;
            $name .= "/" if $selected->is_dir;

            my $position = $selected_index + 1;
            my $selected_count = scalar(grep { $_->is_selected } @$files);

            if ($selected_count > 0) {
                sprintf("[%d/%d] (%d selected) %s", $position, $total_files, $selected_count, $name);
            } else {
                sprintf("[%d/%d] %s", $position, $total_files, $name);
            }
        };

        # Append search status if search query exists
        my $search_status = $self->get_search_status();
        return $base_status . $search_status;
    }

    method _render_status_bar() {
        return unless $is_active;
        my $status_text = $self->_status_text();
        $on_status_change->($status_text);
    }

    method toggle_selection() {
        return unless @$files;

        my $item = $files->[$selected_index];
        $item->toggle_selected();

        # Render to show selection change
        $self->_render();

        # Move cursor down after toggling selection for easy multi-selection
        $self->move_cursor(1);
    }

    method get_files_to_operate() {
        return [] unless @$files;

        my $selected_items = [grep { $_->is_selected } @$files];

        if (@$selected_items) {
            return $selected_items;
        } else {
            return [$files->[$selected_index]];
        }
    }

    method reload_directory() {
        # Remember the file the cursor was on
        my $current_file_path = @$files ? $files->[$selected_index]->stringify : undef;

        $self->_load_directory();

        if (@$files) {
            # Try to find the same file in the reloaded list
            my $new_index;
            for my ($i, $file) (indexed @$files) {
                next unless defined $current_file_path;
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
        } else {
            # Empty directory: reset selection to 0
            $selected_index = 0;
        }

        $self->_render();
    }

    # Search methods
    method update_search($query) {
        $last_search_query = $query;
        $self->_update_matches();

        my $match_indices = $self->_get_match_indices();
        if (@$match_indices) {
            $selected_index = $match_indices->[0];
            $last_match_pos = 1;  # Set initial position to first match
        } else {
            $last_match_pos = undef;  # Clear position if no matches
        }

        $self->_render();
        return scalar(@$match_indices);  # Return match count for caller to display
    }

    method clear_search() {
        $self->update_search("");
    }

    method next_match() {
        my $indices = $self->_get_match_indices();
        return if @$indices == 0;

        my $next = first { $_ > $selected_index } @$indices;
        $selected_index = $next // $indices->[0];

        # Update last match position
        my $idx = firstidx { $_ == $selected_index } @$indices;
        $last_match_pos = $idx + 1 if $idx >= 0;

        $self->_render();
    }

    method prev_match() {
        my $indices = $self->_get_match_indices();
        return if @$indices == 0;

        my $prev = first { $_ < $selected_index } reverse @$indices;
        $selected_index = $prev // $indices->[-1];

        # Update last match position
        my $idx = firstidx { $_ == $selected_index } @$indices;
        $last_match_pos = $idx + 1 if $idx >= 0;

        $self->_render();
    }

    method _update_matches() {
        # Clear all match flags
        for my $item (@$files) {
            $item->set_match(false);
        }

        return if $last_search_query eq "";

        my $query_lc = fc($last_search_query);

        for my $item (@$files) {
            if (index(fc($item->basename), $query_lc) >= 0) {
                $item->set_match(true);
            }
        }
    }

    method _get_match_indices() {
        my $indices = [];
        for my ($i, $item) (indexed @$files) {
            push @$indices, $i if $item->is_match;
        }
        return $indices;
    }

    method _find_file_index($path_str) {
        for my ($i, $file) (indexed @$files) {
            return $i if $file->stringify eq $path_str;
        }
        return undef;
    }

    method get_search_status() {
        # Return search status for display after search mode exits
        # (During search mode, DoubleDrive manages the status bar directly)
        my $match_indices = $self->_get_match_indices();
        if ($last_search_query ne "" && @$match_indices) {
            my $total = scalar(@$match_indices);
            return " [search: $last_search_query ($last_match_pos/$total)]";
        }
        return "";
    }
}
