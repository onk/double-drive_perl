use v5.42;
use experimental 'class';

class DoubleDrive::App {
    use Tickit;
    use DoubleDrive::KeyDispatcher;
    use DoubleDrive::CommandInput;
    use DoubleDrive::Layout;
    use DoubleDrive::Command::Delete;
    use DoubleDrive::Command::Copy;

    field $tickit :reader;
    field $left_pane :reader;    # :reader for testing
    field $right_pane :reader;   # :reader for testing
    field $active_pane :reader;  # :reader for testing
    field $status_bar :reader;
    field $float_box :reader;  # FloatBox for dialogs
    field $key_dispatcher :reader;
    field $cmdline_key_handler;  # Event handler ID for command line input mode key events
    field $cmdline_input;        # CommandInput instance for managing input buffer

    ADJUST {
        my $components = DoubleDrive::Layout->build(left_path => '.', right_path => '.');

        $float_box = $components->{float_box};
        $status_bar = $components->{status_bar};
        $left_pane = $components->{left_pane};
        $right_pane = $components->{right_pane};

        $active_pane = $left_pane;

        $tickit = Tickit->new(root => $float_box);

        $tickit->later(sub {
            # Disable mouse tracking to allow text selection and copy/paste
            $tickit->term->setctl_int("mouse", 0);

            $left_pane->after_window_attached();
            $right_pane->after_window_attached();
        });

        $key_dispatcher = DoubleDrive::KeyDispatcher->new(tickit => $tickit);
        $self->_setup_keybindings();
        $cmdline_input = DoubleDrive::CommandInput->new();
    }

    method _setup_keybindings() {
        $key_dispatcher->bind_normal('Down' => sub { $active_pane->move_selection(1) });
        $key_dispatcher->bind_normal('Up' => sub { $active_pane->move_selection(-1) });
        $key_dispatcher->bind_normal('Enter' => sub { $active_pane->enter_selected() });
        $key_dispatcher->bind_normal('Tab' => sub { $self->switch_pane() });
        $key_dispatcher->bind_normal('Backspace' => sub { $active_pane->change_directory("..") });
        $key_dispatcher->bind_normal(' ' => sub { $active_pane->toggle_selection() });
        $key_dispatcher->bind_normal('d' => sub {
            DoubleDrive::Command::Delete->new(
            )->execute($self);
        });
        $key_dispatcher->bind_normal('c' => sub {
            DoubleDrive::Command::Copy->new(
            )->execute($self);
        });
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

    method run() {
        $tickit->run;
    }
}
