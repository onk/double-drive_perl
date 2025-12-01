use v5.42;
use experimental 'class';

class DoubleDrive::Command::Delete {
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
        my $targets = $self->_collect_targets($active_pane) or return;

        my $message = $self->_build_message($targets);
        await $self->_confirm_future($app, $message);
        await $self->_perform_future($app, $active_pane, $targets);
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

    method _build_message($files) {
        my $count = scalar(@$files);
        my $file_list = join(", ", map { display_name($_->basename) } @$files);
        return $count == 1
            ? "Delete $file_list?"
            : "Delete $count files ($file_list)?";
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

    method _perform_future($app, $pane, $files) {
        return Future->call(sub {
            my $failed = DoubleDrive::FileManipulator->delete_files($files);

            # Reload directory after deletion
            $pane->reload_directory();

            $self->_alert_errors($app, $failed) if @$failed;
            return Future->done;
        });
    }

    method _alert_errors($app, $failed) {
        my $error_msg = "Failed to delete:\n" .
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
