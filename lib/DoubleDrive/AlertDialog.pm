use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::AlertDialog :isa(DoubleDrive::Dialog::Base) {
    use DoubleDrive::Dialog::Base;

    field $on_ack :param = sub {};

    method _instruction_text() {
        return "Press Enter or Escape to close";
    }

    method _bind_keys() {
        $self->key_dispatcher->bind_dialog('Enter'  => sub { $self->_ack() });
        $self->key_dispatcher->bind_dialog('Escape' => sub { $self->_ack() });
    }

    method _ack() {
        $self->close();
        $on_ack->();
    }

}
