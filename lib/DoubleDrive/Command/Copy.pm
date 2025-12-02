use v5.42;
use experimental 'class';

class DoubleDrive::Command::Copy {
    use DoubleDrive::TextUtil qw(display_name);
    use DoubleDrive::FileManipulator;
    use Future;
    use Future::AsyncAwait;

    field $pending_future;
    field $context :param;

    # Context を展開
    field $active_pane;
    field $opposite_pane;
    field $on_status_change;
    field $on_confirm;
    field $on_alert;

    ADJUST {
        $active_pane = $context->active_pane;
        $opposite_pane = $context->opposite_pane;
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

        return if $self->_guard_same_directory($active_pane, $opposite_pane);
        return if $self->_guard_copy_into_self($files, $opposite_pane);

        my $dest_path = $opposite_pane->current_path;
        my $existing = DoubleDrive::FileManipulator->overwrite_targets($files, $dest_path);

        try {
            if (!@$existing) {
                await $self->_perform_future($opposite_pane, $files);
                return;
            }

            my $message = $self->_build_message($files, $existing);
            await $on_confirm->($message, 'Confirm');
            await $self->_perform_future($opposite_pane, $files);
        }
        catch ($e) {
            return if $self->_is_cancelled($e);
            await $on_alert->("Failed to copy:\n- (copy): $e", 'Error');
        }
    }

    method _guard_same_directory($src_pane, $dest_pane) {
        my $src_path = $src_pane->current_path;
        my $dest_path = $dest_pane->current_path;

        if ($src_path->stringify eq $dest_path->stringify) {
            $on_status_change->("Copy skipped: source and destination are the same");
            return true;
        }

        return false;
    }

    method _guard_copy_into_self($files, $dest_pane) {
        my $dest_path = $dest_pane->current_path;

        if (DoubleDrive::FileManipulator->copy_into_self($files, $dest_path)) {
            $on_status_change->("Copy skipped: destination is inside source");
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

    method _is_cancelled($e) {
        # When await sees a failed Future, it throws the failure's first arg as an exception.
        # We treat anything beginning with "cancelled" as a user cancel.
        return "$e" =~ /^cancelled\b/;
    }

    async method _perform_future($dest_pane, $files) {
        my $dest_path = $dest_pane->current_path;
        my $failed = DoubleDrive::FileManipulator->copy_files($files, $dest_path);

        # Reload destination pane directory
        $dest_pane->reload_directory();

        if (@$failed) {
            my $error_msg = "Failed to copy:\n" .
                join("\n", map { "- " . display_name($_->{file}) . ": $_->{error}" } @$failed);
            await $on_alert->($error_msg, 'Error');
        }
    }
}
