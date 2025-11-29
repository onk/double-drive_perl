use v5.42;
use experimental 'class';

class DoubleDrive {
    use Tickit;
    use Tickit::Widget::FloatBox;
    use Tickit::Widget::HBox;
    use Tickit::Widget::VBox;
    use Tickit::Widget::Static;
    use Encode qw(decode_utf8);
    use DoubleDrive::Pane;
    use DoubleDrive::ConfirmDialog;
    use DoubleDrive::AlertDialog;
    use DoubleDrive::KeyDispatcher;
    use DoubleDrive::FileManipulator;

    field $tickit;
    field $left_pane :reader;    # :reader for testing
    field $right_pane :reader;   # :reader for testing
    field $active_pane :reader;  # :reader for testing
    field $status_bar;
    field $float_box;  # FloatBox for dialogs
    field $key_dispatcher;

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

        $key_dispatcher = DoubleDrive::KeyDispatcher->new(tickit => $tickit);

        # Trigger initial render after event loop starts and widgets are attached
        $tickit->later(sub {
            # Disable mouse tracking to allow text selection and copy/paste
            $tickit->term->setctl_int("mouse", 0);

            $left_pane->after_window_attached();
            $right_pane->after_window_attached();
        });
    }

    method _setup_keybindings() {
        $key_dispatcher->bind_normal('Down' => sub { $active_pane->move_selection(1) });
        $key_dispatcher->bind_normal('Up' => sub { $active_pane->move_selection(-1) });
        $key_dispatcher->bind_normal('Enter' => sub { $active_pane->enter_selected() });
        $key_dispatcher->bind_normal('Tab' => sub { $self->switch_pane() });
        $key_dispatcher->bind_normal('Backspace' => sub { $active_pane->change_directory("..") });
        $key_dispatcher->bind_normal(' ' => sub { $active_pane->toggle_selection() });
        $key_dispatcher->bind_normal('d' => sub { $self->delete_files() });
        $key_dispatcher->bind_normal('c' => sub { $self->copy_files() });
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
        my $file_list = join(", ", map { decode_utf8($_->basename) } @$files);
        my $message = $count == 1
            ? "Delete $file_list?"
            : "Delete $count files ($file_list)?";

        DoubleDrive::ConfirmDialog->new(
            tickit => $tickit,
            float_box => $float_box,
            key_dispatcher => $key_dispatcher,
            title => 'Confirm',
            message => $message,
            on_confirm => sub { $self->_perform_delete($files) },
        )->show();
    }

    method _perform_delete($files) {
        my $failed = DoubleDrive::FileManipulator->delete_files($files);

        # Reload directory
        $active_pane->reload_directory();

        # Show error dialog if any deletions failed
        if (@$failed) {
            my $error_msg = "Failed to delete:\n" .
                join("\n", map { "- " . decode_utf8($_->{file}) . ": $_->{error}" } @$failed);
            DoubleDrive::AlertDialog->new(
                tickit => $tickit,
                float_box => $float_box,
                key_dispatcher => $key_dispatcher,
                title => 'Error',
                message => $error_msg,
            )->show();
        }
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

        # Prevent copying a directory into its own descendant (would recurse forever)
        if (DoubleDrive::FileManipulator->copy_into_self($files, $dest_path)) {
            $status_bar->set_text("Copy skipped: destination is inside source");
            return;
        }

        # Check for existing files in destination
        my $existing = DoubleDrive::FileManipulator->overwrite_targets($files, $dest_path);

        # If no files will be overwritten, copy directly without confirmation
        if (!@$existing) {
            $self->_perform_copy($files, $dest_path, $dest_pane);
            return;
        }

        # Show confirmation dialog only when overwriting
        my $count = scalar(@$files);
        my $file_list = join(", ", map { decode_utf8($_->basename) } @$files);
        my $existing_list = join(", ", map { decode_utf8($_) } @$existing);
        my $message;

        if ($count == 1) {
            $message = "Overwrite $existing_list?";
        } else {
            my $existing_count = scalar(@$existing);
            $message = "Copy $count files ($file_list)?\n$existing_count file(s) will be overwritten: $existing_list";
        }

        DoubleDrive::ConfirmDialog->new(
            tickit => $tickit,
            float_box => $float_box,
            key_dispatcher => $key_dispatcher,
            title => 'Confirm',
            message => $message,
            on_confirm => sub { $self->_perform_copy($files, $dest_path, $dest_pane) },
        )->show();
    }

    method _perform_copy($files, $dest_path, $dest_pane) {
        my $failed = DoubleDrive::FileManipulator->copy_files($files, $dest_path);

        # Reload destination pane directory
        $dest_pane->reload_directory();

        # Show error dialog if any copies failed
        if (@$failed) {
            my $error_msg = "Failed to copy:\n" .
                join("\n", map { "- " . decode_utf8($_->{file}) . ": $_->{error}" } @$failed);
            DoubleDrive::AlertDialog->new(
                tickit => $tickit,
                float_box => $float_box,
                key_dispatcher => $key_dispatcher,
                title => 'Error',
                message => $error_msg,
            )->show();
        }
    }

    method run() {
        $tickit->run;
    }
}
