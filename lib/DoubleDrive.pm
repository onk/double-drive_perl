use v5.42;
use experimental 'class';

use Tickit;
use Tickit::Widget::HBox;
use DoubleDrive::Pane;

class DoubleDrive {
    field $tickit;
    field $left_pane;
    field $right_pane;
    field $active_pane;

    ADJUST {
        $self->_build_ui();
        $self->_setup_keybindings();
    }

    method _build_ui() {
        my $hbox = Tickit::Widget::HBox->new(spacing => 1);

        $left_pane = DoubleDrive::Pane->new(path => '.');
        $right_pane = DoubleDrive::Pane->new(path => '.');

        $hbox->add($left_pane->widget, expand => 1);
        $hbox->add($right_pane->widget, expand => 1);

        $tickit = Tickit->new(root => $hbox);
        $active_pane = $left_pane;
        $left_pane->set_active(true);

        # Trigger initial render after event loop starts and widgets are attached
        $tickit->later(sub {
            $left_pane->after_window_attached();
            $right_pane->after_window_attached();
        });
    }

    method _setup_keybindings() {
        $tickit->bind_key('Down' => sub { $active_pane->move_selection(1) });
        $tickit->bind_key('Up' => sub { $active_pane->move_selection(-1) });
        $tickit->bind_key('Enter' => sub { $active_pane->enter_selected() });
        $tickit->bind_key('Tab' => sub { $self->switch_pane() });
        $tickit->bind_key('Backspace' => sub { $active_pane->change_directory("..") });
    }

    method switch_pane() {
        $active_pane->set_active(false);
        $active_pane = ($active_pane == $left_pane) ? $right_pane : $left_pane;
        $active_pane->set_active(true);
    }

    method run() {
        $tickit->run;
    }
}
