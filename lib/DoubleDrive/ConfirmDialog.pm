use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::ConfirmDialog {
    use Tickit::Widget::Static;
    use Tickit::Widget::VBox;
    use Tickit::Widget::Frame;
    field $message :param;
    field $title :param = 'Confirm';
    field $on_confirm :param;  # Callback for Yes/OK
    field $on_cancel :param;   # Callback for No/Escape
    field $on_show :param;     # Callback when dialog is shown
    field $on_close :param;    # Callback when dialog is closed
    field $tickit :param;
    field $float_box :param;  # FloatBox widget
    field $mode :param = 'confirm';  # 'confirm' (Yes/No) or 'alert' (OK only)
    field $dialog_widget;
    field $float;  # Float object returned by add_float
    field $selected_option = 'yes';  # 'yes' or 'no' (for confirm mode)
    field $instruction_widget;  # Widget to update when selection changes

    ADJUST {
        $self->_build_widget();
    }

    method _build_widget() {
        my $vbox = Tickit::Widget::VBox->new;

        # Message
        my $msg_widget = Tickit::Widget::Static->new(
            text => $message,
            align => "left",
        );

        # Instruction
        $instruction_widget = Tickit::Widget::Static->new(
            text => $self->_format_options(),
            align => "left",
        );

        $vbox->add($msg_widget, expand => 1);
        $vbox->add($instruction_widget);

        $dialog_widget = Tickit::Widget::Frame->new(
            style => { linetype => "double" },
            title => $title,
        )->set_child($vbox);
    }

    method _format_options() {
        if ($mode eq 'alert') {
            return "Press Enter or Escape to close";
        }

        if ($selected_option eq 'yes') {
            return "> [Y]es   [N]o";
        } else {
            return "  [Y]es > [N]o";
        }
    }

    method show() {
        # Notify that dialog is being shown
        $on_show->();

        # Add dialog to float box (more centered)
        $float = $float_box->add_float(
            child => $dialog_widget,
            top => 8,
            left => 20,
            right => -20,
        );
    }

    method toggle_option() {
        return if $mode eq 'alert';  # No toggle in alert mode

        $selected_option = ($selected_option eq 'yes') ? 'no' : 'yes';
        $instruction_widget->set_text($self->_format_options());
    }

    method execute_selected() {
        if ($mode eq 'alert') {
            $self->confirm();  # Always confirm in alert mode
        } elsif ($selected_option eq 'yes') {
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

    method close() {
        # Remove dialog from float box
        $float->remove if $float;

        # Notify that dialog is closed
        $on_close->();
    }
}
