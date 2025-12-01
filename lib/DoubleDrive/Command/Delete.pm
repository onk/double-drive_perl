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
        my $targets = $active_pane->get_files_to_operate();
        return unless @$targets;

        my $message = $self->_build_message($targets);
        try {
            await $self->_confirm_future($app, $message);
            await $self->_perform_future($app, $active_pane, $targets);
        }
        catch ($e) {
            return if $self->_is_cancelled($e);
            $self->_alert_errors($app, [{ file => "(delete)", error => $e }]);
        }
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
        my $scope = $app->key_dispatcher->dialog_scope;

        DoubleDrive::ConfirmDialog->new(
            tickit => $app->tickit,
            float_box => $app->float_box,
            key_scope => $scope,
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

        my $scope = $app->key_dispatcher->dialog_scope;
        DoubleDrive::AlertDialog->new(
            tickit => $app->tickit,
            float_box => $app->float_box,
            key_scope => $scope,
            title => 'Error',
            message => $error_msg,
        )->show();
    }
}
