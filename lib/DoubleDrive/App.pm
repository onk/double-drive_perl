use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::App {
    use Tickit;
    use DoubleDrive::KeyDispatcher;
    use DoubleDrive::CommandInput;
    use DoubleDrive::Layout;
    use DoubleDrive::Command::Delete;
    use DoubleDrive::Command::Copy;
    use DoubleDrive::CommandContext;
    use DoubleDrive::ConfirmDialog;
    use DoubleDrive::AlertDialog;
    use Future::AsyncAwait;

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
        $key_dispatcher->bind_normal('j' => sub { $active_pane->move_selection(1) });
        $key_dispatcher->bind_normal('k' => sub { $active_pane->move_selection(-1) });
        $key_dispatcher->bind_normal('h' => sub { $self->switch_pane() if $active_pane == $right_pane });
        $key_dispatcher->bind_normal('l' => sub { $self->switch_pane() if $active_pane == $left_pane });
        $key_dispatcher->bind_normal('Enter' => sub { $active_pane->enter_selected() });
        $key_dispatcher->bind_normal('Tab' => sub { $self->switch_pane() });
        $key_dispatcher->bind_normal('Backspace' => sub { $active_pane->change_directory("..") });
        $key_dispatcher->bind_normal(' ' => sub { $active_pane->toggle_selection() });
        $key_dispatcher->bind_normal('d' => sub {
            DoubleDrive::Command::Delete->new(
                context => $self->command_context()
            )->execute();
        });
        $key_dispatcher->bind_normal('c' => sub {
            DoubleDrive::Command::Copy->new(
                context => $self->command_context()
            )->execute();
        });
        $key_dispatcher->bind_normal('/' => sub { $self->enter_search_cmdline() });
        $key_dispatcher->bind_normal('n' => sub { $active_pane->next_match() });
        $key_dispatcher->bind_normal('N' => sub { $active_pane->prev_match() });
        $key_dispatcher->bind_normal('Escape' => sub { $active_pane->clear_search() });
    }

    # Generic command line input mode with common key handling framework
    # TODO: Use named arguments when available (v5.44)
    method enter_cmdline_mode($callbacks) {
        # Prevent duplicate handler registration
        $self->_cleanup_cmdline_handler() if $cmdline_key_handler;

        $key_dispatcher->enter_command_line_mode();
        $cmdline_input->clear();

        # Initialize callback
        $callbacks->{on_init}->() if $callbacks->{on_init};

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
                    $callbacks->{on_cancel}->() if $callbacks->{on_cancel};
                    $self->exit_cmdline_mode();
                    return 1;
                } elsif ($key eq 'Enter') {
                    $callbacks->{on_execute}->($cmdline_input->buffer) if $callbacks->{on_execute};
                    $self->exit_cmdline_mode();
                    return 1;
                } elsif ($key eq 'Backspace') {
                    $cmdline_input->delete_char();
                    $callbacks->{on_change}->($cmdline_input->buffer) if $callbacks->{on_change};
                    return 1;
                } elsif ($type eq "text") {
                    $cmdline_input->add_char($key);
                    $callbacks->{on_change}->($cmdline_input->buffer) if $callbacks->{on_change};
                    return 1;
                }

                return 0;
            }
        );
    }

    # Search-specific command line mode
    method enter_search_cmdline() {
        $self->enter_cmdline_mode({
            on_init => sub {
                $active_pane->update_search("");
                $status_bar->set_text("/ (no matches)");
            },
            on_change => sub ($query) {
                my $match_count = $active_pane->update_search($query);
                my $status = $match_count > 0
                    ? "/$query ($match_count matches)"
                    : "/$query (no matches)";
                $status_bar->set_text($status);
            },
            on_execute => sub ($query) {
                # Keep search results for n/N navigation
            },
            on_cancel => sub {
                $active_pane->clear_search();
            }
        });
    }

    method exit_cmdline_mode() {
        $key_dispatcher->exit_command_line_mode();
        $self->_cleanup_cmdline_handler();
        # Return control to active pane (redraw status bar and file list)
        $active_pane->_render();
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

    method command_context() {
        return DoubleDrive::CommandContext->new(
            active_pane => $active_pane,
            opposite_pane => $self->opposite_pane(),
            on_status_change => sub ($text) { $status_bar->set_text($text) },
            on_confirm => async sub ($msg, $title = 'Confirm') {
                await $self->confirm_dialog($msg, $title)
            },
            on_alert => async sub ($msg, $title = 'Error') {
                await $self->alert_dialog($msg, $title)
            },
        );
    }

    async method confirm_dialog($message, $title = 'Confirm') {
        my $f = Future->new;
        my $scope = $key_dispatcher->dialog_scope;

        DoubleDrive::ConfirmDialog->new(
            tickit => $tickit,
            float_box => $float_box,
            key_scope => $scope,
            title => $title,
            message => $message,
            on_confirm => sub { $f->done(1) },
            on_cancel => sub { $f->fail("cancelled") },
        )->show();

        return await $f;
    }

    async method alert_dialog($message, $title = 'Error') {
        my $f = Future->new;
        my $scope = $key_dispatcher->dialog_scope;

        DoubleDrive::AlertDialog->new(
            tickit => $tickit,
            float_box => $float_box,
            key_scope => $scope,
            title => $title,
            message => $message,
            on_ack => sub { $f->done },
        )->show();

        return await $f;
    }

    method run() {
        $tickit->run;
    }
}
