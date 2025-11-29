use v5.42;
use experimental 'class';

class DoubleDrive::KeyDispatcher {
    field $tickit :param;
    field $dialog_mode = false;
    field $search_mode = false;
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

    method enter_search_mode() {
        $search_mode = true;
    }

    method exit_search_mode() {
        $search_mode = false;
    }

    method is_in_search_mode() {
        return $search_mode;
    }

    method _ensure_binding($key) {
        return if $bound_keys->{$key};

        $tickit->bind_key($key => sub {
            return if $search_mode;  # Search mode keys handled separately via bind_event
            my $cb = $dialog_mode ? $dialog_keys->{$key} : $normal_keys->{$key};
            $cb->() if $cb;
        });

        $bound_keys->{$key} = 1;
    }
}
