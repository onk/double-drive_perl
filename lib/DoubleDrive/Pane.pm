use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Pane {
    use Tickit::Widget::Frame;
    use Tickit::Pen;
    use DoubleDrive::FileListView;
    use DoubleDrive::TextUtil qw(display_name);
    use Path::Tiny qw(path);
    use List::Util qw(min first);
    use List::MoreUtils qw(firstidx);

    field $path :param;              # Initial path (string or Path::Tiny object) passed to constructor
    field $on_status_change :param;
    field $is_active :param :reader = false;  # :reader for testing
    field $current_path :reader;     # Current directory as Path::Tiny object (:reader for testing)
    field $files = [];
    field $selected_index :reader = 0;  # :reader for testing
    field $scroll_offset = 0;        # First visible item index
    field $selected_files = {};      # Hash of selected file paths (stringified path as key)
    field $widget :reader;
    field $file_list_view;

    # Search state
    field $last_search_query = "";
    field $last_search_matches = [];      # File paths (strings) that match last query
    field $last_match_pos;                # Last position in match list (1-indexed)

    ADJUST {
        $current_path = path($path);
        $self->_build_widget();
        $self->_load_directory();
        $self->_render();
    }

    method _build_widget() {
        $file_list_view = DoubleDrive::FileListView->new(text => "");

        $widget = Tickit::Widget::Frame->new(
            style => { linetype => "single" },
            title => display_name($current_path->absolute->stringify),
        )->set_child($file_list_view);
    }

    method _load_directory() {
        # Get all entries and sort alphabetically (case-insensitive)
        $files = [sort { fc($a->basename) cmp fc($b->basename) } $current_path->children];

        # Clear selection when loading a new directory
        $selected_files = {};
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
        my $match_set = { map { $_ => 1 } @$last_search_matches };

        for my $index ($scroll_offset .. $end_index) {
            my $file = $files->[$index];

            my $is_selected_file = exists $selected_files->{$file->stringify};
            my $is_cursor = ($is_active && $index == $selected_index);
            push @$rows, {
                path       => $file,
                is_cursor  => $is_cursor,
                is_selected => $is_selected_file,
                is_match   => $match_set->{$file->stringify} ? 1 : 0,
            };
        }

        $file_list_view->set_rows($rows);
    }

    method _render() {
        $self->_render_file_list();
        $self->_render_status_bar();
    }

    method move_selection($delta) {
        return unless @$files;

        my $new_index = $selected_index + $delta;

        if ($new_index >= 0 && $new_index < scalar(@$files)) {
            $selected_index = $new_index;
            $self->_render();
        }
    }

    method change_directory($new_path) {
        my $previous_path = $current_path;

        # Handle both string paths and Path::Tiny objects
        my $path_obj = $new_path isa Path::Tiny
            ? $new_path
            : path($current_path, $new_path);
        $current_path = $path_obj->realpath;
        $selected_index = 0;
        $scroll_offset = 0;
        $widget->set_title(display_name($current_path->stringify));

        # Clear search state when changing directories
        $last_search_query = "";
        $last_search_matches = [];
        $last_match_pos = undef;

        $self->_load_directory();

        # When explicitly moving to parent (".."), select the directory we came from if it exists
        if (!($new_path isa Path::Tiny) && $new_path eq "..") {
            if (@$files) {
                my $new_index;
                for my ($i, $file) (indexed @$files) {
                    if ($file->stringify eq $previous_path->stringify) {
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
            my $name = display_name($selected->basename);
            $name .= "/" if $selected->is_dir;

            my $position = $selected_index + 1;
            my $selected_count = scalar(keys %$selected_files);

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
        return [] unless @$files;

        # Return selected files if any exist, otherwise return current file
        if (keys %$selected_files) {
            return [grep { exists $selected_files->{$_->stringify} } @$files];
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

        if (@$last_search_matches) {
            my $first_idx = $self->_find_file_index($last_search_matches->[0]);
            $selected_index = $first_idx if defined $first_idx;
            $last_match_pos = 1;  # Set initial position to first match
        } else {
            $last_match_pos = undef;  # Clear position if no matches
        }

        $self->_render();
        return scalar(@$last_search_matches);  # Return match count for caller to display
    }

    method clear_search() {
        $last_search_query = "";
        $last_search_matches = [];
        $last_match_pos = undef;
        $self->_render();
    }

    method next_match() {
        return if @$last_search_matches == 0;

        my $indices = [map { $self->_find_file_index($_) // () } @$last_search_matches];
        return unless @$indices;

        my $next = first { $_ > $selected_index } @$indices;
        $selected_index = $next // $indices->[0];

        # Update last match position
        my $current_file = $files->[$selected_index]->stringify;
        my $idx = firstidx { $_ eq $current_file } @$last_search_matches;
        $last_match_pos = $idx + 1 if $idx >= 0;

        $self->_render();
    }

    method prev_match() {
        return if @$last_search_matches == 0;

        my $indices = [map { $self->_find_file_index($_) // () } @$last_search_matches];
        return unless @$indices;

        my $prev = first { $_ < $selected_index } reverse @$indices;
        $selected_index = $prev // $indices->[-1];

        # Update last match position
        my $current_file = $files->[$selected_index]->stringify;
        my $idx = firstidx { $_ eq $current_file } @$last_search_matches;
        $last_match_pos = $idx + 1 if $idx >= 0;

        $self->_render();
    }

    method _update_matches() {
        $last_search_matches = [];

        return if $last_search_query eq "";

        my $query_lc = fc($last_search_query);

        for my $file (@$files) {
            my $name = display_name($file->basename);
            if (index(fc($name), $query_lc) >= 0) {
                push @$last_search_matches, $file->stringify;
            }
        }
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
        if ($last_search_query ne "" && @$last_search_matches) {
            my $total = scalar(@$last_search_matches);
            return " [search: $last_search_query ($last_match_pos/$total)]";
        }
        return "";
    }
}
