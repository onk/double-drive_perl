use v5.42;
use experimental 'class';

use Tickit;
use Tickit::Widget::HBox;
use Tickit::Widget::VBox;
use Tickit::Widget::Static;
use DoubleDrive::Pane;

class DoubleDrive {
    field $tickit;
    field $left_pane :reader;    # :reader for testing
    field $right_pane :reader;   # :reader for testing
    field $active_pane :reader;  # :reader for testing
    field $status_bar;

    ADJUST {
        $self->_build_ui();
        $self->_setup_keybindings();
    }

    method _build_ui() {
        # Create vertical box to hold panes and status bar
        my $vbox = Tickit::Widget::VBox->new;

        # Create horizontal box for dual panes
        my $hbox = Tickit::Widget::HBox->new(spacing => 1);

        # Create status bar
        $status_bar = Tickit::Widget::Static->new(
            text => "",
            align => "left",
        );

        # Create panes with status change callback
        $left_pane = DoubleDrive::Pane->new(
            path => '.',
            on_status_change => sub ($text) { $status_bar->set_text($text) }
        );
        $right_pane = DoubleDrive::Pane->new(
            path => '.',
            on_status_change => sub ($text) { $status_bar->set_text($text) }
        );

        $hbox->add($left_pane->widget, expand => 1);
        $hbox->add($right_pane->widget, expand => 1);

        # Add panes and status bar to vertical box
        $vbox->add($hbox, expand => 1);
        $vbox->add($status_bar);

        $tickit = Tickit->new(root => $vbox);
        $active_pane = $left_pane;
        $left_pane->set_active(true);

        # Trigger initial render after event loop starts and widgets are attached
        $tickit->later(sub {
            # Disable mouse tracking to allow text selection and copy/paste
            $tickit->term->setctl_int("mouse", 0);

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
