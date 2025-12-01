use v5.42;
use experimental 'class';

class DoubleDrive::KeyDispatcher::DialogScope {
    field $dispatcher :param;

    ADJUST {
        $dispatcher->_start_dialog_scope();
    }

    method bind($key, $callback) {
        $dispatcher->bind_dialog($key, $callback);
    }

    method DESTROY {
        $dispatcher->_end_dialog_scope();
    }
}
