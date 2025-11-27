use v5.42;
use experimental 'class';

use Tickit;
use Tickit::Widget::HBox;
use DoubleDrive::Pane;

class DoubleDrive {
    field $tickit;
    field $active_pane;

    ADJUST {
        $self->_build_ui();
        $self->_setup_keybindings();
    }

    method _build_ui() {
        my $hbox = Tickit::Widget::HBox->new(spacing => 1);

        my $left = DoubleDrive::Pane->new(path => '.');
        my $right = DoubleDrive::Pane->new(path => '.');

        $hbox->add($left->widget, expand => 1);
        $hbox->add($right->widget, expand => 1);

        $tickit = Tickit->new(root => $hbox);
        $active_pane = $left;
    }

    method _setup_keybindings() {
        $tickit->bind_key('Down' => sub { $active_pane->move_selection(1) });
        $tickit->bind_key('Up' => sub { $active_pane->move_selection(-1) });
        $tickit->bind_key('Enter' => sub { $active_pane->enter_selected() });
    }

    method run() {
        $tickit->run;
    }
}
