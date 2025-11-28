use v5.42;
use experimental 'class';

use Tickit;
use Tickit::Widget::FloatBox;
use Tickit::Widget::HBox;
use Tickit::Widget::VBox;
use Tickit::Widget::Static;
use DoubleDrive::Pane;
use DoubleDrive::ConfirmDialog;

class DoubleDrive {
    field $tickit;
    field $left_pane :reader;    # :reader for testing
    field $right_pane :reader;   # :reader for testing
    field $active_pane :reader;  # :reader for testing
    field $status_bar;
    field $float_box;  # FloatBox for dialogs
    field $dialog_open = false;  # Flag to track if dialog is open
    field $normal_keys = {};  # Normal mode key bindings
    field $dialog_keys = {};  # Dialog mode key bindings

    ADJUST {
        $self->_build_ui();
        $self->_setup_keybindings();
    }

    method _build_ui() {
        # Create FloatBox for overlaying dialogs
        $float_box = Tickit::Widget::FloatBox->new;

        # Create main vertical box
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

        # Set VBox as base child of FloatBox
        $float_box->set_base_child($vbox);

        $tickit = Tickit->new(root => $float_box);
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

    method normal_bind_key($key, $callback) {
        $normal_keys->{$key} = $callback;
        $self->_setup_key_dispatch($key);
    }

    method dialog_bind_key($key, $callback) {
        $dialog_keys->{$key} = $callback;
        $self->_setup_key_dispatch($key);
    }

    method _setup_key_dispatch($key) {
        $tickit->bind_key($key => sub {
            if ($dialog_open && exists $dialog_keys->{$key}) {
                $dialog_keys->{$key}->();
            } elsif (!$dialog_open && exists $normal_keys->{$key}) {
                $normal_keys->{$key}->();
            }
        });
    }

    method _setup_keybindings() {
        $self->normal_bind_key('Down' => sub { $active_pane->move_selection(1) });
        $self->normal_bind_key('Up' => sub { $active_pane->move_selection(-1) });
        $self->normal_bind_key('Enter' => sub { $active_pane->enter_selected() });
        $self->normal_bind_key('Tab' => sub { $self->switch_pane() });
        $self->normal_bind_key('Backspace' => sub { $active_pane->change_directory("..") });
        $self->normal_bind_key(' ' => sub { $active_pane->toggle_selection() });
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
