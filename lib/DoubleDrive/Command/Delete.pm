use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Command::Delete {
    use DoubleDrive::TextUtil qw(display_name);
    use DoubleDrive::FileManipulator;
    use Future;
    use Future::AsyncAwait;

    field $context :param;
    field $pending_future;
    field $active_pane;
    field $on_status_change;
    field $on_confirm;
    field $on_alert;

    ADJUST {
        $active_pane = $context->active_pane;
        $on_status_change = $context->on_status_change;
        $on_confirm = $context->on_confirm;
        $on_alert = $context->on_alert;
    }

    method execute() {
        my $future = $self->_execute_async();
        $pending_future = $future;
        $future->on_ready(sub { $pending_future = undef });
        return $future;
    }

    async method _execute_async() {
        my $files = $active_pane->get_files_to_operate();
        return unless @$files;

        my $message = $self->_build_message($files);
        try {
            await $on_confirm->($message, 'Confirm');
            await $self->_perform_future($files);
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

    async method _perform_future($files) {
        my $failed = DoubleDrive::FileManipulator->delete_files($files);

        # Reload directory after deletion
        $active_pane->reload_directory();

        if (@$failed) {
            my $error_msg = "Failed to delete:\n" .
                join("\n", map { "- " . display_name($_->{file}) . ": $_->{error}" } @$failed);
            await $on_alert->($error_msg, 'Error');
        }
    }
}
