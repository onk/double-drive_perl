use v5.42;
use experimental 'class';

class DoubleDrive::Command::Copy {
    use DoubleDrive::TextUtil qw(display_name);
    use DoubleDrive::ConfirmDialog;
    use DoubleDrive::AlertDialog;
    use DoubleDrive::FileManipulator;

    method execute($app) {
        my $active_pane = $app->active_pane;
        my $dest_pane = $app->opposite_pane();

        my $files = $self->_collect_targets($active_pane) or return;

        return if $self->_guard_same_directory($active_pane, $dest_pane, $app->status_bar);
        return if $self->_guard_copy_into_self($files, $dest_pane, $app->status_bar);

        my $dest_path = $dest_pane->current_path;
        my $existing = DoubleDrive::FileManipulator->overwrite_targets($files, $dest_path);

        my $perform = sub { $self->_perform($app, $dest_pane, $files) };

        if (!@$existing) {
            $perform->();
            return;
        }

        my $message = $self->_build_message($files, $existing);
        $self->_confirm($app, $message, $perform);
    }

    method _collect_targets($pane) {
        my $files = $pane->get_files_to_operate();
        return unless @$files;

        # Skip parent directory entry
        my $parent = $pane->current_path->parent;
        my $filtered = [grep { $_ ne $parent } @$files];
        return unless @$filtered;

        return $filtered;
    }

    method _guard_same_directory($src_pane, $dest_pane, $status_bar) {
        my $src_path = $src_pane->current_path;
        my $dest_path = $dest_pane->current_path;

        if ($src_path->stringify eq $dest_path->stringify) {
            $status_bar->set_text("Copy skipped: source and destination are the same");
            return true;
        }

        return false;
    }

    method _guard_copy_into_self($files, $dest_pane, $status_bar) {
        my $dest_path = $dest_pane->current_path;

        if (DoubleDrive::FileManipulator->copy_into_self($files, $dest_path)) {
            $status_bar->set_text("Copy skipped: destination is inside source");
            return true;
        }

        return false;
    }

    method _build_message($files, $existing) {
        my $count = scalar(@$files);
        my $file_list = join(", ", map { display_name($_->basename) } @$files);
        my $existing_list = join(", ", map { display_name($_) } @$existing);

        if ($count == 1) {
            return "Overwrite $existing_list?";
        }

        my $existing_count = scalar(@$existing);
        return "Copy $count files ($file_list)?\n$existing_count file(s) will be overwritten: $existing_list";
    }

    method _confirm($app, $message, $on_confirm) {
        DoubleDrive::ConfirmDialog->new(
            tickit => $app->tickit,
            float_box => $app->float_box,
            key_dispatcher => $app->key_dispatcher,
            title => 'Confirm',
            message => $message,
            on_confirm => $on_confirm,
        )->show();
    }

    method _perform($app, $dest_pane, $files) {
        my $dest_path = $dest_pane->current_path;
        my $failed = DoubleDrive::FileManipulator->copy_files($files, $dest_path);

        # Reload destination pane directory
        $dest_pane->reload_directory();

        $self->_alert_errors($app, $failed) if @$failed;
    }

    method _alert_errors($app, $failed) {
        my $error_msg = "Failed to copy:\n" .
            join("\n", map { "- " . display_name($_->{file}) . ": $_->{error}" } @$failed);

        DoubleDrive::AlertDialog->new(
            tickit => $app->tickit,
            float_box => $app->float_box,
            key_dispatcher => $app->key_dispatcher,
            title => 'Error',
            message => $error_msg,
        )->show();
    }
}
