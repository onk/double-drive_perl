use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Dialog::SortDialog :isa(DoubleDrive::Dialog::Base) {
    use DoubleDrive::Dialog::Base;

    field $on_execute :param;       # Callback with selected sort option
    field $on_cancel :param = sub {};
    field $selected_index = 0;     # Index of currently selected option

    # Available sort options (ordered for display)
    field $sort_option_order = ['n', 's', 'm', 'e'];
    field $sort_options = {
        n => { sort_key => 'name',  label => '[N]ame' },
        s => { sort_key => 'size',  label => '[S]ize' },
        m => { sort_key => 'mtime', label => '[M]odified time' },
        e => { sort_key => 'ext',   label => '[E]xtension' },
    };

    method _instruction_text() {
        my $lines = [];
        for my ($i, $key) (indexed @$sort_option_order) {
            my $opt = $sort_options->{$key};
            my $prefix = ($i == $selected_index) ? '> ' : '  ';
            push @$lines, $prefix . $opt->{label};
        }
        return join("\n", @$lines);
    }

    method _bind_keys() {
        $self->key_scope->bind('j' => sub { $self->move_selection(1) });
        $self->key_scope->bind('k' => sub { $self->move_selection(-1) });
        $self->key_scope->bind('Down' => sub { $self->move_selection(1) });
        $self->key_scope->bind('Up' => sub { $self->move_selection(-1) });
        $self->key_scope->bind('n' => sub { $self->select_option('n') });
        $self->key_scope->bind('N' => sub { $self->select_option('n') });
        $self->key_scope->bind('s' => sub { $self->select_option('s') });
        $self->key_scope->bind('S' => sub { $self->select_option('s') });
        $self->key_scope->bind('m' => sub { $self->select_option('m') });
        $self->key_scope->bind('M' => sub { $self->select_option('m') });
        $self->key_scope->bind('e' => sub { $self->select_option('e') });
        $self->key_scope->bind('E' => sub { $self->select_option('e') });
        $self->key_scope->bind('Enter' => sub { $self->execute_selected() });
        $self->key_scope->bind('Escape' => sub { $self->cancel() });
    }

    method move_selection($delta) {
        my $new_index = $selected_index + $delta;
        if ($new_index >= 0 && $new_index < scalar(@$sort_option_order)) {
            $selected_index = $new_index;
            $self->_update_instruction();
        }
    }

    method select_option($key) {
        my $opt = $sort_options->{$key};
        return unless $opt;
        $self->close();
        $on_execute->($opt->{sort_key});
    }

    method execute_selected() {
        my $key = $sort_option_order->[$selected_index];
        $self->select_option($key);
    }

    method cancel() {
        $self->close();
        $on_cancel->();
    }
}
