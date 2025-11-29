use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::ConfirmDialog :isa(DoubleDrive::Dialog::Base) {
    use DoubleDrive::Dialog::Base;

    field $on_confirm :param;  # Callback for Yes/OK
    field $on_cancel :param = sub {};   # Callback for No/Escape
    field $selected_option = 'yes';  # 'yes' or 'no'

    method _instruction_text() {
        if ($selected_option eq 'yes') {
            return "> [Y]es   [N]o";
        } else {
            return "  [Y]es > [N]o";
        }
    }

    method _bind_keys() {
        $self->key_dispatcher->bind_dialog('y' => sub { $self->confirm() });
        $self->key_dispatcher->bind_dialog('Y' => sub { $self->confirm() });
        $self->key_dispatcher->bind_dialog('n' => sub { $self->cancel() });
        $self->key_dispatcher->bind_dialog('N' => sub { $self->cancel() });
        $self->key_dispatcher->bind_dialog('Tab' => sub { $self->toggle_option() });
        $self->key_dispatcher->bind_dialog('Enter' => sub { $self->execute_selected() });
        $self->key_dispatcher->bind_dialog('Escape' => sub { $self->cancel() });
    }

    method toggle_option() {
        $selected_option = ($selected_option eq 'yes') ? 'no' : 'yes';
        $self->_update_instruction();
    }

    method execute_selected() {
        if ($selected_option eq 'yes') {
            $self->confirm();
        } else {
            $self->cancel();
        }
    }

    method confirm() {
        $self->close();
        $on_confirm->();
    }

    method cancel() {
        $self->close();
        $on_cancel->();
    }
}
