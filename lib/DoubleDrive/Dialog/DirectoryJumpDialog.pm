use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Dialog::DirectoryJumpDialog :isa(DoubleDrive::Dialog::Base) {
    use DoubleDrive::Dialog::Base;

    field $directories :param;
    field $on_execute :param;
    field $on_cancel :param = sub { };
    field $selected_index = 0;

    method _instruction_text() {
        my $lines = [];
        for my ($i, $dir) (indexed @$directories) {
            my $prefix = $i == $selected_index ? '> ' : '  ';
            my $key_hint = "[$dir->{key}] ";
            push @$lines, $prefix . $key_hint . $dir->{name};
        }
        return join("\n", @$lines);
    }

    method _bind_keys() {
        $self->key_scope->bind('j' => sub { $self->_move_selection(1) });
        $self->key_scope->bind('k' => sub { $self->_move_selection(-1) });
        $self->key_scope->bind('Down' => sub { $self->_move_selection(1) });
        $self->key_scope->bind('Up' => sub { $self->_move_selection(-1) });
        $self->key_scope->bind('Enter' => sub { $self->_execute_selected() });
        $self->key_scope->bind('Escape' => sub { $self->_cancel() });

        for my ($i, $dir) (indexed @$directories) {
            my $key = $dir->{key};
            $self->_bind_direct_key($key, $i);
        }
    }

    method _bind_direct_key($key, $index) {
        $self->key_scope->bind($key => sub { $self->_select_and_execute($index) });
    }

    method _move_selection($delta) {
        my $new_index = $selected_index + $delta;
        if ($new_index >= 0 && $new_index < scalar(@$directories)) {
            $selected_index = $new_index;
            $self->_update_instruction();
        }
    }

    method _select_and_execute($index) {
        $selected_index = $index;
        $self->_update_instruction();
        $self->_execute_selected();
    }

    method _execute_selected() {
        my $dir = $directories->[$selected_index];
        $self->close();
        $on_execute->($dir->{path});
    }

    method _cancel() {
        $self->close();
        $on_cancel->();
    }
}
