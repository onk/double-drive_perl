use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Pane {
    use Tickit::Widget::Frame;
    use Tickit::Widget::Static;
    use Tickit::Pen;
    use DoubleDrive::FileListView;
    use DoubleDrive::FileListItem;
    use DoubleDrive::ArchiveItem;
    use Path::Tiny qw(path);
    use List::Util qw(min first);
    use List::MoreUtils qw(firstidx);

    field $path :param;              # Initial path (string or Path::Tiny object) passed to constructor
    field $on_status_change :param;
    field $is_active :param :reader = false;  # :reader for testing
    field $current_path :reader;     # Current directory as FileListItem or ArchiveItem object (:reader for testing)
    field $files :reader = [];       # Array of FileListItem or ArchiveItem objects (:reader for testing)
    field $selected_index :reader = 0;  # :reader for testing
    field $scroll_offset = 0;        # First visible item index
    field $widget :reader;
    field $file_list_view;
    field $archive_root;             # Path to archive file when inside archive (undef otherwise)

    # Search state
    field $last_search_query = "";
    field $last_match_pos;                # Last position in match list (1-indexed)

    # Sort state
    field $sort_key = 'name';             # Current sort key: 'name', 'size', 'mtime', 'ext'

    ADJUST {
        $current_path = DoubleDrive::FileListItem->new(path => path($path)->realpath);
        $self->_build_widget();
        $self->_load_directory();
        $self->_render();
    }

    method in_archive() {
        return defined $archive_root;
    }

    method _build_widget() {
        $file_list_view = DoubleDrive::FileListView->new(text => "");

        $widget = Tickit::Widget::Frame->new(
            style => { linetype => "single" },
            title => $self->_format_path_title($current_path->stringify),
        )->set_child($file_list_view);
    }

    method _load_directory() {
        # Get all entries as FileListItem, and sort according to current sort_key
        $files = $self->_sort_files($current_path->children);
    }

    method _sort_files($items) {
        if ($sort_key eq 'size') {
            return [sort {
                $b->is_dir <=> $a->is_dir ||
                $b->size <=> $a->size ||
                fc($a->basename) cmp fc($b->basename)
            } @$items];
        } elsif ($sort_key eq 'mtime') {
            return [sort {
                $b->is_dir <=> $a->is_dir ||
                $b->mtime <=> $a->mtime ||
                fc($a->basename) cmp fc($b->basename)
            } @$items];
        } elsif ($sort_key eq 'ext') {
            return [sort {
                $b->is_dir <=> $a->is_dir ||
                fc($a->extname) cmp fc($b->extname) ||
                fc($a->basename) cmp fc($b->basename)
            } @$items];
        } else {  # 'name' is default
            return [sort {
                $b->is_dir <=> $a->is_dir ||
                fc($a->basename) cmp fc($b->basename)
            } @$items];
        }
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
        my $exited_from_archive;

        # Handle FileListItem, ArchiveItem, and string paths
        if ($new_path isa DoubleDrive::FileListItem) {
            $current_path = $new_path->realpath;
        } elsif ($new_path isa DoubleDrive::ArchiveItem) {
            $current_path = $new_path;
        } else {
            # String path: handle ".." and absolute paths
            if ($new_path eq "..") {
                # Navigate to parent directory
                my $parent = $current_path->parent;

                # Check if we exited from archive to filesystem
                if ($self->in_archive && $parent isa DoubleDrive::FileListItem) {
                    $exited_from_archive = $archive_root;
                    $archive_root = undef;
                }
                $current_path = $parent;
            } elsif ($new_path =~ m{^/}) {
                # Absolute path
                my $new_item_path = path($new_path);
                return unless $new_item_path->is_dir;
                $current_path = DoubleDrive::FileListItem->new(path => $new_item_path->realpath);
            } else {
                # Invalid path
                return;
            }
        }

        $selected_index = 0;
        $scroll_offset = 0;
        $widget->set_title($self->_format_path_title($current_path->stringify));

        # Clear search state when changing directories
        # Note: We don't call clear_search() here to avoid double rendering.
        # _load_directory() creates new FileListItem objects, so is_match flags
        # will be reset automatically.
        $last_search_query = "";
        $last_match_pos = undef;

        $self->_load_directory();

        # Select the item we came from when moving to parent
        if ($new_path eq ".." && @$files) {
            my $target_path = $exited_from_archive // $previous_path->stringify;
            for my ($i, $item) (indexed @$files) {
                if ($item->stringify eq $target_path) {
                    $selected_index = $i;
                    last;
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
        } elsif ($selected->is_archive) {
            $self->enter_archive($selected);
        }
    }

    method enter_archive($archive_item) {
        my $archive_root_item;
        try {
            $archive_root_item = DoubleDrive::ArchiveItem->new_from_archive($archive_item);
        } catch($e) {
            $on_status_change->("Cannot read archive: $e");
            return;
        }

        $archive_root = $archive_item->stringify;
        $self->change_directory($archive_root_item);
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

    method clear_selection() {
        for my $file (@$files) {
            $file->toggle_selected() if $file->is_selected;
        }
        $self->_render();
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

    method _format_path_title($path_str) {
        # Replace home directory with ~ to shorten display
        my $home = path("~")->absolute->stringify;
        if (index($path_str, $home) == 0) {
            my $relative = substr($path_str, length($home));
            return "~" . $relative;
        }
        return $path_str;
    }

    method set_sort($new_sort_key) {
        return if $sort_key eq $new_sort_key;  # No change needed

        # Remember current file for repositioning cursor
        my $current_file_path = @$files ? $files->[$selected_index]->stringify : undef;

        $sort_key = $new_sort_key;
        $self->_load_directory();

        # Try to keep cursor on the same file after resorting
        if (@$files && defined $current_file_path) {
            my $new_index;
            for my ($i, $file) (indexed @$files) {
                if ($file->stringify eq $current_file_path) {
                    $new_index = $i;
                    last;
                }
            }
            $selected_index = $new_index if defined $new_index;
        }

        $self->_render();
    }

    method start_preview() {
        # Detach file list view from frame to keep frame/title but remove contents for overlay preview
        # Insert an empty Static widget instead of undef so Frame keeps a valid child
        $widget->set_child(Tickit::Widget::Static->new(text => ""));
        $self->_render();
    }

    method stop_preview() {
        # Reattach file list view to frame after preview ends
        $widget->set_child($file_list_view);
        $self->_render();
    }
}
