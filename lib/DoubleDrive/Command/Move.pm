use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Command::Move {
    use DoubleDrive::FileManipulator;
    use Future;
    use Future::AsyncAwait;

    field $context :param;
    field $pending_future;
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
        my $file_items = $active_pane->get_files_to_operate();
        return unless @$file_items;

        return if $self->_guard_same_directory();
        return if $self->_guard_move_into_self($file_items);

        my $dest_item = $opposite_pane->current_path;
        my $existing_files = DoubleDrive::FileManipulator->overwrite_targets($file_items, $dest_item);

        try {
            if (@$existing_files) {
                my $message = $self->_build_overwrite_message($file_items, $existing_files);
                await $on_confirm->($message, 'Confirm');
            }
            await $self->_perform_future($file_items);
        } catch ($e) {
            return if $self->_is_cancelled($e);
            await $on_alert->("Failed to move:\n- (move): $e", 'Error');
        }
    }

    method _guard_same_directory() {
        my $src_path = $active_pane->current_path;
        my $dest_path = $opposite_pane->current_path;

        if ($src_path->stringify eq $dest_path->stringify) {
            $on_status_change->("Move skipped: source and destination are the same");
            return true;
        }

        return false;
    }

    method _guard_move_into_self($file_items) {
        my $dest_item = $opposite_pane->current_path;

        if (DoubleDrive::FileManipulator->copy_into_self($file_items, $dest_item)) {
            $on_status_change->("Move skipped: destination is inside source");
            return true;
        }

        return false;
    }

    method _build_overwrite_message($file_items, $existing_files) {
        my $count = scalar(@$file_items);
        my $file_list = join(", ", map { $_->basename } @$file_items);
        my $existing_list = join(", ", @$existing_files);

        if ($count == 1) {
            return "Overwrite $existing_list?";
        }

        my $existing_count = scalar(@$existing_files);
        return "Move $count files ($file_list)?\n$existing_count file(s) will be overwritten: $existing_list";
    }

    method _is_cancelled($e) {
        # When await sees a failed Future, it throws the failure's first arg as an exception.
        # We treat anything beginning with "cancelled" as a user cancel.
        return "$e" =~ /^cancelled\b/;
    }

    async method _perform_future($file_items) {
        my $dest_item = $opposite_pane->current_path;
        my $failed = DoubleDrive::FileManipulator->move_files($file_items, $dest_item);

        # Reload both panes as files are moved (removed from source, added to dest)
        $active_pane->reload_directory();
        $opposite_pane->reload_directory();

        if (@$failed) {
            my $error_msg = "Failed to move:\n" . join("\n", map { "- $_->{file}: $_->{error}" } @$failed);
            await $on_alert->($error_msg, 'Error');
        }
    }
}
