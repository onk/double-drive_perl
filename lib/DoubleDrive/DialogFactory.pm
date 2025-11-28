use v5.42;
use experimental 'class';

class DoubleDrive::DialogFactory {
    use DoubleDrive::ConfirmDialog;

    field $tickit :param;
    field $float_box :param;
    field $bind_key :param;   # Code ref to bind dialog-specific keys
    field $on_open :param;    # Called when dialog is shown (e.g., set dialog_open flag)
    field $on_close :param;   # Called when dialog closes (e.g., reset dialog state)

    # TODO: Switch to keyword args when available (clearer call sites, fewer position mistakes)
    method show_confirm($message, $on_confirm, $on_cancel = sub {}) {
        my $dialog;
        $dialog = DoubleDrive::ConfirmDialog->new(
            message => $message,
            tickit => $tickit,
            float_box => $float_box,
            on_show => sub {
                $on_open->();
                $bind_key->('y' => sub { $dialog->confirm() });
                $bind_key->('Y' => sub { $dialog->confirm() });
                $bind_key->('n' => sub { $dialog->cancel() });
                $bind_key->('N' => sub { $dialog->cancel() });
                $bind_key->('Tab' => sub { $dialog->toggle_option() });
                $bind_key->('Enter' => sub { $dialog->execute_selected() });
                $bind_key->('Escape' => sub { $dialog->cancel() });
            },
            on_close => sub {
                $on_close->();
            },
            on_confirm => sub { $on_confirm->() },
            on_cancel => sub { $on_cancel->() },
        );

        $dialog->show();
        return $dialog;
    }

    # TODO: Switch to keyword args when available (clearer call sites, fewer position mistakes)
    method show_alert($message, $on_ack = sub {}) {
        my $dialog;
        $dialog = DoubleDrive::ConfirmDialog->new(
            message => $message,
            tickit => $tickit,
            float_box => $float_box,
            mode => 'alert',
            on_show => sub {
                $on_open->();
                $bind_key->('Enter' => sub { $dialog->confirm() });
                $bind_key->('Escape' => sub { $dialog->cancel() });
            },
            on_close => sub {
                $on_close->();
            },
            on_confirm => sub { $on_ack->() },
            on_cancel => sub { $on_ack->() },  # Same behavior for alert dialogs
        );

        $dialog->show();
        return $dialog;
    }
}
