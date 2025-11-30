use v5.42;
use experimental 'class';

class DoubleDrive::App {
    use Tickit;
    use Tickit::Widget::FloatBox;
    use Tickit::Widget::HBox;
    use Tickit::Widget::VBox;
    use Tickit::Widget::Static;
    use DoubleDrive::TextUtil qw(display_name);
    use DoubleDrive::Pane;
    use DoubleDrive::ConfirmDialog;
    use DoubleDrive::AlertDialog;
    use DoubleDrive::KeyDispatcher;
    use DoubleDrive::FileManipulator;
    use DoubleDrive::CommandInput;

    field $tickit;
    field $left_pane :reader;    # :reader for testing
    field $right_pane :reader;   # :reader for testing
    field $active_pane :reader;  # :reader for testing
    field $status_bar;
    field $float_box;  # FloatBox for dialogs
    field $key_dispatcher;
    field $cmdline_key_handler;  # Event handler ID for command line input mode key events
    field $cmdline_input;        # CommandInput instance for managing input buffer

    ADJUST {
        $self->_build_ui();
        $self->_setup_keybindings();
        $cmdline_input = DoubleDrive::CommandInput->new();
    }

    method _build_ui() {
        # Create FloatBox for overlaying dialogs
        $float_box = Tickit::Widget::FloatBox->new;

        # Create main vertical box
        my $vbox = Tickit::Widget::VBox->new;

        # Create horizontal box for dual panes
        my $hbox = Tickit::Widget::HBox->new(spacing => 1);

        # Create status bar
        $status_bar = Tickit::Widget::Static->new(
            text => "",
            align => "left",
        );

        # Create panes with status change callback
        $left_pane = DoubleDrive::Pane->new(
            path => '.',
            on_status_change => sub ($text) { $status_bar->set_text($text) }
        );
        $right_pane = DoubleDrive::Pane->new(
            path => '.',
            on_status_change => sub ($text) { $status_bar->set_text($text) }
        );

        $hbox->add($left_pane->widget, expand => 1);
        $hbox->add($right_pane->widget, expand => 1);

        # Add panes and status bar to vertical box
        $vbox->add($hbox, expand => 1);
        $vbox->add($status_bar);

        # Set VBox as base child of FloatBox
        $float_box->set_base_child($vbox);

        $tickit = Tickit->new(root => $float_box);
        $active_pane = $left_pane;
        $left_pane->set_active(true);

        $key_dispatcher = DoubleDrive::KeyDispatcher->new(tickit => $tickit);

        # Trigger initial render after event loop starts and widgets are attached
        $tickit->later(sub {
            # Disable mouse tracking to allow text selection and copy/paste
            $tickit->term->setctl_int("mouse", 0);

            $left_pane->after_window_attached();
            $right_pane->after_window_attached();
        });
    }

    method _setup_keybindings() {
        $key_dispatcher->bind_normal('Down' => sub { $active_pane->move_selection(1) });
        $key_dispatcher->bind_normal('Up' => sub { $active_pane->move_selection(-1) });
        $key_dispatcher->bind_normal('Enter' => sub { $active_pane->enter_selected() });
        $key_dispatcher->bind_normal('Tab' => sub { $self->switch_pane() });
        $key_dispatcher->bind_normal('Backspace' => sub { $active_pane->change_directory("..") });
        $key_dispatcher->bind_normal(' ' => sub { $active_pane->toggle_selection() });
        $key_dispatcher->bind_normal('d' => sub { $self->delete_files() });
        $key_dispatcher->bind_normal('c' => sub { $self->copy_files() });
        $key_dispatcher->bind_normal('/' => sub { $self->enter_search_mode() });
        $key_dispatcher->bind_normal('n' => sub { $active_pane->next_match() });
        $key_dispatcher->bind_normal('N' => sub { $active_pane->prev_match() });
        $key_dispatcher->bind_normal('Escape' => sub { $active_pane->clear_search() });
    }

    method enter_search_mode() {
        # Prevent duplicate handler registration
        $self->_cleanup_cmdline_handler() if $cmdline_key_handler;

        $key_dispatcher->enter_command_line_mode();
        $cmdline_input->clear();

        # Initialize with empty search
        $active_pane->update_search("");
        $status_bar->set_text("/ (no matches)");

        # Capture all key events including multibyte characters (Japanese, etc.)
        # This allows command line input with any Unicode input
        my $rootwin = $tickit->rootwin;
        $cmdline_key_handler = $rootwin->bind_event(
            key => sub {
                my ($win, $event, $info, $data) = @_;
                return 0 unless $key_dispatcher->is_in_command_line_mode();

                my $type = $info->type;
                my $key = $info->str;

                if ($key eq 'Escape') {
                    # Clear search and exit mode
                    $key_dispatcher->exit_command_line_mode();
                    $active_pane->clear_search();
                    return 1;
                } elsif ($key eq 'Enter') {
                    # Keep search results for n/N navigation
                    $self->exit_search_mode();
                    return 1;
                } elsif ($key eq 'Backspace') {
                    $cmdline_input->delete_char();
                    my $query = $cmdline_input->buffer;
                    my $match_count = $active_pane->update_search($query);

                    # Update status bar
                    my $status = $match_count > 0
                        ? "/$query ($match_count matches)"
                        : "/$query (no matches)";
                    $status_bar->set_text($status);
                    return 1;
                } elsif ($type eq "text") {
                    $cmdline_input->add_char($key);
                    my $query = $cmdline_input->buffer;
                    my $match_count = $active_pane->update_search($query);

                    # Update status bar
                    my $status = $match_count > 0
                        ? "/$query ($match_count matches)"
                        : "/$query (no matches)";
                    $status_bar->set_text($status);
                    return 1;
                }

                return 0;
            }
        );
    }

    method exit_search_mode() {
        $key_dispatcher->exit_command_line_mode();
        $self->_cleanup_cmdline_handler();

        # Return to normal status display (managed by Pane)
        $active_pane->_notify_status_change();
    }

    method _cleanup_cmdline_handler() {
        return unless $cmdline_key_handler;

        my $rootwin = $tickit->rootwin;
        $rootwin->unbind_event_id($cmdline_key_handler);
        $cmdline_key_handler = undef;
    }

    method switch_pane() {
        $active_pane->set_active(false);
        $active_pane = ($active_pane == $left_pane) ? $right_pane : $left_pane;
        $active_pane->set_active(true);
    }

    method opposite_pane() {
        return ($active_pane == $left_pane) ? $right_pane : $left_pane;
    }

    method delete_files() {
        my $files = $active_pane->get_files_to_operate();
        return unless @$files;

        # Skip parent directory
        $files = [grep { $_ ne $active_pane->current_path->parent } @$files];
        return unless @$files;

        my $count = scalar(@$files);
        my $file_list = join(", ", map { display_name($_->basename) } @$files);
        my $message = $count == 1
            ? "Delete $file_list?"
            : "Delete $count files ($file_list)?";

        DoubleDrive::ConfirmDialog->new(
            tickit => $tickit,
            float_box => $float_box,
            key_dispatcher => $key_dispatcher,
            title => 'Confirm',
            message => $message,
            on_confirm => sub { $self->_perform_delete($files) },
        )->show();
    }

    method _perform_delete($files) {
        my $failed = DoubleDrive::FileManipulator->delete_files($files);

        # Reload directory
        $active_pane->reload_directory();

        # Show error dialog if any deletions failed
        if (@$failed) {
            my $error_msg = "Failed to delete:\n" .
                join("\n", map { "- " . display_name($_->{file}) . ": $_->{error}" } @$failed);
            DoubleDrive::AlertDialog->new(
                tickit => $tickit,
                float_box => $float_box,
                key_dispatcher => $key_dispatcher,
                title => 'Error',
                message => $error_msg,
            )->show();
        }
    }

    method copy_files() {
        my $files = $active_pane->get_files_to_operate();
        return unless @$files;

        # Skip parent directory
        $files = [grep { $_ ne $active_pane->current_path->parent } @$files];
        return unless @$files;

        # Get destination pane (opposite of active pane)
        my $dest_pane = $self->opposite_pane();
        my $dest_path = $dest_pane->current_path;

        # Skip self-copy
        if ($active_pane->current_path->stringify eq $dest_path->stringify) {
            $status_bar->set_text("Copy skipped: source and destination are the same");
            return;
        }

        # Prevent copying a directory into its own descendant (would recurse forever)
        if (DoubleDrive::FileManipulator->copy_into_self($files, $dest_path)) {
            $status_bar->set_text("Copy skipped: destination is inside source");
            return;
        }

        # Check for existing files in destination
        my $existing = DoubleDrive::FileManipulator->overwrite_targets($files, $dest_path);

        # If no files will be overwritten, copy directly without confirmation
        if (!@$existing) {
            $self->_perform_copy($files, $dest_path, $dest_pane);
            return;
        }

        # Show confirmation dialog only when overwriting
        my $count = scalar(@$files);
        my $file_list = join(", ", map { display_name($_->basename) } @$files);
        my $existing_list = join(", ", map { display_name($_) } @$existing);
        my $message;

        if ($count == 1) {
            $message = "Overwrite $existing_list?";
        } else {
            my $existing_count = scalar(@$existing);
            $message = "Copy $count files ($file_list)?\n$existing_count file(s) will be overwritten: $existing_list";
        }

        DoubleDrive::ConfirmDialog->new(
            tickit => $tickit,
            float_box => $float_box,
            key_dispatcher => $key_dispatcher,
            title => 'Confirm',
            message => $message,
            on_confirm => sub { $self->_perform_copy($files, $dest_path, $dest_pane) },
        )->show();
    }

    method _perform_copy($files, $dest_path, $dest_pane) {
        my $failed = DoubleDrive::FileManipulator->copy_files($files, $dest_path);

        # Reload destination pane directory
        $dest_pane->reload_directory();

        # Show error dialog if any copies failed
        if (@$failed) {
            my $error_msg = "Failed to copy:\n" .
                join("\n", map { "- " . decode_utf8($_->{file}) . ": $_->{error}" } @$failed);
            DoubleDrive::AlertDialog->new(
                tickit => $tickit,
                float_box => $float_box,
                key_dispatcher => $key_dispatcher,
                title => 'Error',
                message => $error_msg,
            )->show();
        }
    }

    method run() {
        $tickit->run;
    }
}
