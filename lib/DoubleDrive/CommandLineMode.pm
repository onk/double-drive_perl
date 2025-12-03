use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::CommandLineMode {
    use DoubleDrive::CommandInput;

    field $tickit :param;
    field $key_dispatcher :param;
    field $cmdline_input;
    field $cmdline_key_handler;  # Event handler ID for cleanup

    ADJUST {
        $cmdline_input = DoubleDrive::CommandInput->new();
    }

    # Generic command line input mode with common key handling framework
    method enter($callbacks) {
        # Prevent duplicate handler registration
        $self->_cleanup_handler() if defined $cmdline_key_handler;

        $key_dispatcher->enter_command_line_mode();
        $cmdline_input->clear();

        # Initialize callback
        $callbacks->{on_init}->() if $callbacks->{on_init};

        # Capture all key events including multibyte characters (Japanese, etc.)
        # This allows command line input with any Unicode input
        my $rootwin = $tickit->rootwin;
        $cmdline_key_handler = $rootwin->bind_event(
            key => sub {
                $self->_handle_key_event($callbacks, @_);
            }
        );
    }

    method exit() {
        $key_dispatcher->exit_command_line_mode();
        $self->_cleanup_handler();
    }

    method _handle_key_event($callbacks, $win, $event, $info, $data) {
        return 0 unless $key_dispatcher->is_in_command_line_mode();

        my $type = $info->type;
        my $key = $info->str;

        if ($key eq 'Escape') {
            $callbacks->{on_cancel}->() if $callbacks->{on_cancel};
            $self->exit();
            return 1;
        } elsif ($key eq 'Enter') {
            $callbacks->{on_execute}->($cmdline_input->buffer) if $callbacks->{on_execute};
            $self->exit();
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

    method _cleanup_handler() {
        return unless defined $cmdline_key_handler;

        my $rootwin = $tickit->rootwin;
        $rootwin->unbind_event_id($cmdline_key_handler);
        $cmdline_key_handler = undef;
    }
}
