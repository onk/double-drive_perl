use v5.42;
use experimental 'class';

class DoubleDrive::Command::Delete {
    use DoubleDrive::TextUtil qw(display_name);
    use DoubleDrive::FileManipulator;
    use Future;
    use Future::AsyncAwait;

    field $pending_future;
    field $on_status_change :param;
    field $on_confirm :param;
    field $on_alert :param;

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
            await $on_confirm->($message, 'Confirm');
            await $self->_perform_future($app, $active_pane, $targets);
        }
        catch ($e) {
            return if $self->_is_cancelled($e);
            await $on_alert->("Failed to delete:\n- (delete): $e", 'Error');
        }
    }

    method _build_message($files) {
        my $count = scalar(@$files);
        my $file_list = join(", ", map { display_name($_->basename) } @$files);
        return $count == 1
            ? "Delete $file_list?"
            : "Delete $count files ($file_list)?";
    }

    method _is_cancelled($e) {
        # When await sees a failed Future, it throws the failure's first arg as an exception.
        # We treat anything beginning with "cancelled" as a user cancel.
        return "$e" =~ /^cancelled\b/;
    }

    async method _perform_future($app, $pane, $files) {
        my $failed = DoubleDrive::FileManipulator->delete_files($files);

        # Reload directory after deletion
        $pane->reload_directory();

        if (@$failed) {
            my $error_msg = "Failed to delete:\n" .
                join("\n", map { "- " . display_name($_->{file}) . ": $_->{error}" } @$failed);
            await $on_alert->($error_msg, 'Error');
        }
    }
}
