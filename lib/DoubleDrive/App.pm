use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::App {
    use Tickit;
    use Path::Tiny qw(path);
    use DoubleDrive::KeyDispatcher;
    use DoubleDrive::CommandLineMode;
    use DoubleDrive::Layout;
    use DoubleDrive::Command::Delete;
    use DoubleDrive::Command::Copy;
    use DoubleDrive::Command::MakeDir;
    use DoubleDrive::CommandContext;
    use DoubleDrive::Dialog::ConfirmDialog;
    use DoubleDrive::Dialog::AlertDialog;
    use DoubleDrive::Dialog::SortDialog;
    use Future::AsyncAwait;
    use DoubleDrive::Command::ViewImage;
    use DoubleDrive::StateStore;

    field $tickit;
    field $state_store;
    field $left_pane :reader;    # :reader for testing
    field $right_pane :reader;   # :reader for testing
    field $active_pane :reader;  # :reader for testing
    field $status_bar;
    field $float_box;  # FloatBox for dialogs
    field $key_dispatcher;
    field $cmdline_mode;         # CommandLineMode instance for managing command line input

    ADJUST {
        $state_store = DoubleDrive::StateStore->new;

        my $paths = $state_store->load_paths();
        my $left_path = $self->_path_or_default($paths->{left_path});
        my $right_path = $self->_path_or_default($paths->{right_path});

        my $components = DoubleDrive::Layout->build(left_path => $left_path, right_path => $right_path);

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
        # View image with kitty icat when selecting a jpg/png/gif
        $key_dispatcher->bind_normal('v' => sub {
            DoubleDrive::Command::ViewImage->new(
                context => $self->command_context(),
                tickit => $tickit,
                dialog_scope => $key_dispatcher->dialog_scope,
                is_left => ($active_pane == $left_pane),
            )->execute();
        });
        $key_dispatcher->bind_normal('/' => sub { $self->enter_search_cmdline() });
        $key_dispatcher->bind_normal('n' => sub { $active_pane->next_match() });
        $key_dispatcher->bind_normal('N' => sub { $active_pane->prev_match() });
        $key_dispatcher->bind_normal('Escape' => sub { $active_pane->clear_search() });
        $key_dispatcher->bind_normal('s' => sub { $self->show_sort_dialog() });
        $key_dispatcher->bind_normal('x' => sub { $self->open_tmux_window() });
        $key_dispatcher->bind_normal('K' => sub {
            DoubleDrive::Command::MakeDir->new(
                context => $self->command_context(),
                cmdline_mode => $cmdline_mode,
            )->execute();
        });
        $key_dispatcher->bind_normal('q' => sub { $self->quit() });
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

        DoubleDrive::Dialog::ConfirmDialog->new(
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

        DoubleDrive::Dialog::AlertDialog->new(
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

        DoubleDrive::Dialog::SortDialog->new(
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

    method open_tmux_window() {
        my $current_dir = $active_pane->current_path->stringify;
        system('tmux', 'new-window', '-c', $current_dir);
        $status_bar->set_text("Opened new tmux window in $current_dir") if $? == 0;
    }

    method quit() {
        $self->confirm_dialog('Do you really want to quit?', 'Quit')->then(sub {
            $state_store->save_paths($left_pane->current_path->stringify, $right_pane->current_path->stringify);
            $tickit->stop;
        })->retain;
    }

    method run() {
        $tickit->run;
    }

    method _path_or_default($path_str) {
        return '.' unless defined $path_str;

        my $p = path($path_str);
        if ($p->exists && $p->is_dir) {
            return $path_str;
        } else {
            return '.';
        }
    }
}
