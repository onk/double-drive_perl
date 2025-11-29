use v5.42;
use experimental 'class';

class DoubleDrive::DialogFactory {
    use DoubleDrive::ConfirmDialog;
    use DoubleDrive::KeyDispatcher;

    field $tickit :param;
    field $float_box :param;
    field $key_dispatcher :param;

    # TODO: Switch to keyword args when available (clearer call sites, fewer position mistakes)
    method show_confirm($message, $on_confirm, $on_cancel = sub {}) {
        my $dialog;
        $dialog = DoubleDrive::ConfirmDialog->new(
            message => $message,
            tickit => $tickit,
            float_box => $float_box,
            on_show => sub {
                $key_dispatcher->enter_dialog_mode();
                $key_dispatcher->bind_dialog('y' => sub { $dialog->confirm() });
                $key_dispatcher->bind_dialog('Y' => sub { $dialog->confirm() });
                $key_dispatcher->bind_dialog('n' => sub { $dialog->cancel() });
                $key_dispatcher->bind_dialog('N' => sub { $dialog->cancel() });
                $key_dispatcher->bind_dialog('Tab' => sub { $dialog->toggle_option() });
                $key_dispatcher->bind_dialog('Enter' => sub { $dialog->execute_selected() });
                $key_dispatcher->bind_dialog('Escape' => sub { $dialog->cancel() });
            },
            on_close => sub {
                $key_dispatcher->exit_dialog_mode();
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
                $key_dispatcher->enter_dialog_mode();
                $key_dispatcher->bind_dialog('Enter' => sub { $dialog->confirm() });
                $key_dispatcher->bind_dialog('Escape' => sub { $dialog->cancel() });
            },
            on_close => sub {
                $key_dispatcher->exit_dialog_mode();
            },
            on_confirm => sub { $on_ack->() },
            on_cancel => sub { $on_ack->() },  # Same behavior for alert dialogs
        );

        $dialog->show();
        return $dialog;
    }
}
