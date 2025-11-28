use v5.42;
use experimental 'class';

class DoubleDrive {
    use Tickit;
    use Tickit::Widget::FloatBox;
    use Tickit::Widget::HBox;
    use Tickit::Widget::VBox;
    use Tickit::Widget::Static;
    use DoubleDrive::Pane;
    use DoubleDrive::ConfirmDialog;
    use File::Copy::Recursive qw(rcopy);

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
        $self->normal_bind_key('d' => sub { $self->delete_files() });
        $self->normal_bind_key('c' => sub { $self->copy_files() });
    }

    method switch_pane() {
        $active_pane->set_active(false);
        $active_pane = ($active_pane == $left_pane) ? $right_pane : $left_pane;
        $active_pane->set_active(true);
    }

    method opposite_pane() {
        return ($active_pane == $left_pane) ? $right_pane : $left_pane;
    }

    method delete_files() {
        my $files = $active_pane->get_files_to_operate();
        return unless @$files;

        # Skip parent directory
        $files = [grep { $_ ne $active_pane->current_path->parent } @$files];
        return unless @$files;

        my $count = scalar(@$files);
        my $file_list = join(", ", map { $_->basename } @$files);
        my $message = $count == 1
            ? "Delete $file_list?"
            : "Delete $count files ($file_list)?";

        my $dialog;
        $dialog = DoubleDrive::ConfirmDialog->new(
            message => $message,
            tickit => $tickit,
            float_box => $float_box,
            on_show => sub {
                $dialog_open = true;
                $self->dialog_bind_key('y' => sub { $dialog->confirm() });
                $self->dialog_bind_key('Y' => sub { $dialog->confirm() });
                $self->dialog_bind_key('n' => sub { $dialog->cancel() });
                $self->dialog_bind_key('N' => sub { $dialog->cancel() });
                $self->dialog_bind_key('Tab' => sub { $dialog->toggle_option() });
                $self->dialog_bind_key('Enter' => sub { $dialog->execute_selected() });
                $self->dialog_bind_key('Escape' => sub { $dialog->cancel() });
            },
            on_close => sub {
                $dialog_open = false;
                $dialog_keys = {};
            },
            on_confirm => sub {
                $self->_perform_delete($files);
            },
            on_cancel => sub {
                # Just restore UI, nothing to do
            }
        );

        $dialog->show();
    }

    method _perform_delete($files) {
        my $failed = [];

        for my $file (@$files) {
            try {
                if ($file->is_dir) {
                    $file->remove_tree;
                } else {
                    $file->remove;
                }
            } catch ($e) {
                push @$failed, { file => $file->basename, error => $e };
            }
        }

        # Reload directory
        $active_pane->reload_directory();

        # Show error dialog if any deletions failed
        if (@$failed) {
            my $error_msg = "Failed to delete:\n" .
                join("\n", map { "- $_->{file}: $_->{error}" } @$failed);
            $self->_show_error_dialog($error_msg);
        }
    }

    method _show_error_dialog($message) {
        my $dialog;
        $dialog = DoubleDrive::ConfirmDialog->new(
            message => $message,
            tickit => $tickit,
            float_box => $float_box,
            mode => 'alert',
            on_show => sub {
                $dialog_open = true;
                $self->dialog_bind_key('Enter' => sub { $dialog->confirm() });
                $self->dialog_bind_key('Escape' => sub { $dialog->cancel() });
            },
            on_close => sub {
                $dialog_open = false;
                $dialog_keys = {};
            },
            on_confirm => sub {
                # Just close the dialog
            },
            on_cancel => sub {
                # Same as confirm for error dialog
            }
        );
        $dialog->show();
    }

    method copy_files() {
        my $files = $active_pane->get_files_to_operate();
        return unless @$files;

        # Skip parent directory
        $files = [grep { $_ ne $active_pane->current_path->parent } @$files];
        return unless @$files;

        # Get destination pane (opposite of active pane)
        my $dest_pane = $self->opposite_pane();
        my $dest_path = $dest_pane->current_path;

        # Skip self-copy
        if ($active_pane->current_path->stringify eq $dest_path->stringify) {
            $status_bar->set_text("Copy skipped: source and destination are the same");
            return;
        }

        # Check for existing files in destination
        my $existing = [];
        for my $file (@$files) {
            my $dest_file = $dest_path->child($file->basename);
            push @$existing, $file->basename if $dest_file->exists;
        }

        # If no files will be overwritten, copy directly without confirmation
        if (!@$existing) {
            $self->_perform_copy($files, $dest_path, $dest_pane);
            return;
        }

        # Show confirmation dialog only when overwriting
        my $count = scalar(@$files);
        my $file_list = join(", ", map { $_->basename } @$files);
        my $existing_list = join(", ", @$existing);
        my $message;

        if ($count == 1) {
            $message = "Overwrite $existing_list?";
        } else {
            my $existing_count = scalar(@$existing);
            $message = "Copy $count files ($file_list)?\n$existing_count file(s) will be overwritten: $existing_list";
        }

        my $dialog;
        $dialog = DoubleDrive::ConfirmDialog->new(
            message => $message,
            tickit => $tickit,
            float_box => $float_box,
            on_show => sub {
                $dialog_open = true;
                $self->dialog_bind_key('y' => sub { $dialog->confirm() });
                $self->dialog_bind_key('Y' => sub { $dialog->confirm() });
                $self->dialog_bind_key('n' => sub { $dialog->cancel() });
                $self->dialog_bind_key('N' => sub { $dialog->cancel() });
                $self->dialog_bind_key('Tab' => sub { $dialog->toggle_option() });
                $self->dialog_bind_key('Enter' => sub { $dialog->execute_selected() });
                $self->dialog_bind_key('Escape' => sub { $dialog->cancel() });
            },
            on_close => sub {
                $dialog_open = false;
                $dialog_keys = {};
            },
            on_confirm => sub {
                $self->_perform_copy($files, $dest_path, $dest_pane);
            },
            on_cancel => sub {
                # Just restore UI, nothing to do
            }
        );

        $dialog->show();
    }

    method _perform_copy($files, $dest_path, $dest_pane) {
        my $failed = [];

        for my $file (@$files) {
            try {
                my $dest_file = $dest_path->child($file->basename);
                if ($file->is_dir) {
                    # For directories, use recursive copy
                    rcopy($file->stringify, $dest_file->stringify)
                        or die "rcopy failed: $!";
                } else {
                    $file->copy($dest_file);
                }
            } catch ($e) {
                push @$failed, { file => $file->basename, error => $e };
            }
        }

        # Reload destination pane directory
        $dest_pane->reload_directory();

        # Show error dialog if any copies failed
        if (@$failed) {
            my $error_msg = "Failed to copy:\n" .
                join("\n", map { "- $_->{file}: $_->{error}" } @$failed);
            $self->_show_error_dialog($error_msg);
        }
    }

    method run() {
        $tickit->run;
    }
}
