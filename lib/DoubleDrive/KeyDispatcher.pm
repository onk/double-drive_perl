use v5.42;
use experimental 'class';

class DoubleDrive::KeyDispatcher {
    field $tickit :param;
    field $dialog_mode = false;
    field $command_line_mode = false;
    field $normal_keys = {};
    field $dialog_keys = {};
    field $bound_keys = {};

    method bind_normal($key, $callback) {
        $normal_keys->{$key} = $callback;
        $self->_ensure_binding($key);
    }

    method bind_dialog($key, $callback) {
        $dialog_keys->{$key} = $callback;
        $self->_ensure_binding($key);
    }

    method enter_dialog_mode() {
        $dialog_mode = true;
    }

    method exit_dialog_mode() {
        $dialog_mode = false;
        $dialog_keys = {};
    }

    method enter_command_line_mode() {
        $command_line_mode = true;
    }

    method exit_command_line_mode() {
        $command_line_mode = false;
    }

    method is_in_command_line_mode() {
        return $command_line_mode;
    }

    method _ensure_binding($key) {
        return if $bound_keys->{$key};

        $tickit->bind_key($key => sub {
            return if $command_line_mode;  # Command line mode keys handled separately via bind_event
            my $cb = $dialog_mode ? $dialog_keys->{$key} : $normal_keys->{$key};
            $cb->() if $cb;
        });

        $bound_keys->{$key} = 1;
    }
}
