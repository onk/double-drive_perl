use v5.42;
use experimental 'class';

class DoubleDrive::KeyDispatcher {
    field $tickit :param;
    field $dialog_mode = false;
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

    method _ensure_binding($key) {
        return if $bound_keys->{$key};

        $tickit->bind_key($key => sub {
            my $cb = $dialog_mode ? $dialog_keys->{$key} : $normal_keys->{$key};
            $cb->() if $cb;
        });

        $bound_keys->{$key} = 1;
    }
}
