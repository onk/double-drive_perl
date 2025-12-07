use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::App {
    use Tickit;
    use DoubleDrive::KeyDispatcher;
    use DoubleDrive::CommandLineMode;
    use DoubleDrive::Layout;
    use DoubleDrive::Command::Delete;
    use DoubleDrive::Command::Copy;
    use DoubleDrive::CommandContext;
    use DoubleDrive::ConfirmDialog;
    use DoubleDrive::AlertDialog;
    use DoubleDrive::SortDialog;
    use Future::AsyncAwait;

    field $tickit;
    field $left_pane :reader;    # :reader for testing
    field $right_pane :reader;   # :reader for testing
    field $active_pane :reader;  # :reader for testing
    field $status_bar;
    field $float_box;  # FloatBox for dialogs
    field $key_dispatcher;
    field $cmdline_mode;         # CommandLineMode instance for managing command line input

    ADJUST {
        my $components = DoubleDrive::Layout->build(left_path => '.', right_path => '.');

        $float_box = $components->{float_box};
        $status_bar = $components->{status_bar};
        $left_pane = $components->{left_pane};
        $right_pane = $components->{right_pane};

        $active_pane = $left_pane;

        $tickit = Tickit->new(root => $float_box);

        $tickit->later(sub {
            # Disable mouse tracking to allow text selection and copy/paste
            $tickit->term->setctl_int("mouse", 0);

            $left_pane->after_window_attached();
            $right_pane->after_window_attached();
        });

        $key_dispatcher = DoubleDrive::KeyDispatcher->new(tickit => $tickit);
        $self->_setup_keybindings();
        $cmdline_mode = DoubleDrive::CommandLineMode->new(
            tickit => $tickit,
            key_dispatcher => $key_dispatcher,
        );
    }

    method _setup_keybindings() {
        $key_dispatcher->bind_normal('Down' => sub { $active_pane->move_cursor(1) });
        $key_dispatcher->bind_normal('Up' => sub { $active_pane->move_cursor(-1) });
        $key_dispatcher->bind_normal('j' => sub { $active_pane->move_cursor(1) });
        $key_dispatcher->bind_normal('k' => sub { $active_pane->move_cursor(-1) });
        $key_dispatcher->bind_normal('h' => sub { $self->switch_pane() if $active_pane == $right_pane });
        $key_dispatcher->bind_normal('l' => sub { $self->switch_pane() if $active_pane == $left_pane });
        $key_dispatcher->bind_normal('g' => sub { $active_pane->move_cursor_top() });
        $key_dispatcher->bind_normal('G' => sub { $active_pane->move_cursor_bottom() });
        $key_dispatcher->bind_normal('Enter' => sub { $active_pane->enter_selected() });
        $key_dispatcher->bind_normal('Tab' => sub { $self->switch_pane() });
        $key_dispatcher->bind_normal('Backspace' => sub { $active_pane->change_directory("..") });
        $key_dispatcher->bind_normal(' ' => sub { $active_pane->toggle_selection() });
        $key_dispatcher->bind_normal('d' => sub {
            DoubleDrive::Command::Delete->new(
                context => $self->command_context()
            )->execute();
        });
        $key_dispatcher->bind_normal('c' => sub {
            DoubleDrive::Command::Copy->new(
                context => $self->command_context()
            )->execute();
        });
        $key_dispatcher->bind_normal('/' => sub { $self->enter_search_cmdline() });
        $key_dispatcher->bind_normal('n' => sub { $active_pane->next_match() });
        $key_dispatcher->bind_normal('N' => sub { $active_pane->prev_match() });
        $key_dispatcher->bind_normal('Escape' => sub { $active_pane->clear_search() });
        $key_dispatcher->bind_normal('s' => sub { $self->show_sort_dialog() });
    }

    # Search-specific command line mode
    method enter_search_cmdline() {
        $cmdline_mode->enter({
            on_init => sub {
                $active_pane->update_search("");
                $status_bar->set_text("/ (no matches)");
            },
            on_change => sub ($query) {
                my $match_count = $active_pane->update_search($query);
                my $status = $match_count > 0
                    ? "/$query ($match_count matches)"
                    : "/$query (no matches)";
                $status_bar->set_text($status);
            },
            on_execute => sub ($query) {
                # Keep search results for n/N navigation
                # Return control to active pane (redraw status bar and file list)
                $active_pane->_render();
            },
            on_cancel => sub {
                $active_pane->clear_search();
                # Return control to active pane (redraw status bar and file list)
                $active_pane->_render();
            }
        });
    }

    method switch_pane() {
        $active_pane->set_active(false);
        $active_pane = ($active_pane == $left_pane) ? $right_pane : $left_pane;
        $active_pane->set_active(true);
    }

    method opposite_pane() {
        return ($active_pane == $left_pane) ? $right_pane : $left_pane;
    }

    method command_context() {
        return DoubleDrive::CommandContext->new(
            active_pane => $active_pane,
            opposite_pane => $self->opposite_pane(),
            on_status_change => sub ($text) { $status_bar->set_text($text) },
            on_confirm => async sub ($msg, $title = 'Confirm') {
                await $self->confirm_dialog($msg, $title)
            },
            on_alert => async sub ($msg, $title = 'Error') {
                await $self->alert_dialog($msg, $title)
            },
        );
    }

    async method confirm_dialog($message, $title = 'Confirm') {
        my $f = Future->new;
        my $scope = $key_dispatcher->dialog_scope;

        DoubleDrive::ConfirmDialog->new(
            tickit => $tickit,
            float_box => $float_box,
            key_scope => $scope,
            title => $title,
            message => $message,
            on_execute => sub { $f->done(1) },
            on_cancel => sub { $f->fail("cancelled") },
        )->show();

        return await $f;
    }

    async method alert_dialog($message, $title = 'Error') {
        my $f = Future->new;
        my $scope = $key_dispatcher->dialog_scope;

        DoubleDrive::AlertDialog->new(
            tickit => $tickit,
            float_box => $float_box,
            key_scope => $scope,
            title => $title,
            message => $message,
            on_ack => sub { $f->done },
        )->show();

        return await $f;
    }

    method show_sort_dialog() {
        my $scope = $key_dispatcher->dialog_scope;

        DoubleDrive::SortDialog->new(
            tickit => $tickit,
            float_box => $float_box,
            key_scope => $scope,
            title => 'Sort by',
            message => 'Select sort order:',
            on_execute => sub ($sort_key) {
                $active_pane->set_sort($sort_key);
            },
            on_cancel => sub {
                # Just close dialog, no action needed
            },
        )->show();
    }

    method run() {
        $tickit->run;
    }
}
