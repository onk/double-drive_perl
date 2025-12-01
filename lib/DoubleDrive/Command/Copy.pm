use v5.42;
use experimental 'class';

class DoubleDrive::Command::Copy {
    use DoubleDrive::TextUtil qw(display_name);
    use DoubleDrive::ConfirmDialog;
    use DoubleDrive::AlertDialog;
    use DoubleDrive::FileManipulator;
    use Future;
    use Future::AsyncAwait;

    field $pending_future;

    method execute($app) {
        my $future = $self->_execute_async($app);
        $pending_future = $future;
        $future->on_ready(sub { $pending_future = undef });
        return $future;
    }

    async method _execute_async($app) {
        my $active_pane = $app->active_pane;
        my $dest_pane = $app->opposite_pane();

        my $files = $active_pane->get_files_to_operate();
        return unless @$files;

        return if $self->_guard_same_directory($active_pane, $dest_pane, $app->status_bar);
        return if $self->_guard_copy_into_self($files, $dest_pane, $app->status_bar);

        my $dest_path = $dest_pane->current_path;
        my $existing = DoubleDrive::FileManipulator->overwrite_targets($files, $dest_path);

        try {
            if (!@$existing) {
                await $self->_perform_future($app, $dest_pane, $files);
                return;
            }

            my $message = $self->_build_message($files, $existing);
            await $self->_confirm_future($app, $message);
            await $self->_perform_future($app, $dest_pane, $files);
        }
        catch ($e) {
            return if $self->_is_cancelled($e);
            $self->_alert_errors($app, [{ file => "(copy)", error => $e }]);
        }
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

    method _confirm_future($app, $message) {
        my $f = Future->new;

        DoubleDrive::ConfirmDialog->new(
            tickit => $app->tickit,
            float_box => $app->float_box,
            key_dispatcher => $app->key_dispatcher,
            title => 'Confirm',
            message => $message,
            on_confirm => sub { $f->done(1) },
            on_cancel => sub { $f->fail("cancelled") },
        )->show();

        return $f;
    }

    method _is_cancelled($e) {
        # When await sees a failed Future, it throws the failure's first arg as an exception.
        # We treat anything beginning with "cancelled" as a user cancel.
        return "$e" =~ /^cancelled\b/;
    }

    method _perform_future($app, $dest_pane, $files) {
        return Future->call(sub {
            my $dest_path = $dest_pane->current_path;
            my $failed = DoubleDrive::FileManipulator->copy_files($files, $dest_path);

            # Reload destination pane directory
            $dest_pane->reload_directory();

            $self->_alert_errors($app, $failed) if @$failed;
        });
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
