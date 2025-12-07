use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Dialog::ConfirmDialog :isa(DoubleDrive::Dialog::Base) {
    use DoubleDrive::Dialog::Base;

    field $on_execute :param;  # Callback for Yes/OK
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
        $self->key_scope->bind('y' => sub { $self->confirm() });
        $self->key_scope->bind('Y' => sub { $self->confirm() });
        $self->key_scope->bind('n' => sub { $self->cancel() });
        $self->key_scope->bind('N' => sub { $self->cancel() });
        $self->key_scope->bind('Tab' => sub { $self->toggle_option() });
        $self->key_scope->bind('Enter' => sub { $self->execute_selected() });
        $self->key_scope->bind('Escape' => sub { $self->cancel() });
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
        $on_execute->();
    }

    method cancel() {
        $self->close();
        $on_cancel->();
    }
}
