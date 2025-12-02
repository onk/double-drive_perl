package DoubleDrive::Command::Copy;
use v5.42;

use DoubleDrive::TextUtil qw(display_name);
use DoubleDrive::FileManipulator;
use Future;
use Future::AsyncAwait;

sub new($class, %args) {
    my $context = $args{context};

    my $self = bless {
        pending_future => undef,
        context => $context,
        active_pane => $context->active_pane,
        opposite_pane => $context->opposite_pane,
        on_status_change => $context->on_status_change,
        on_confirm => $context->on_confirm,
        on_alert => $context->on_alert,
    }, $class;

    return $self;
}

sub execute($self) {
    my $future = $self->_execute_async();
    $self->{pending_future} = $future;
    $future->on_ready(sub { $self->{pending_future} = undef });
    return $future;
}

async sub _execute_async($self) {
    my $active_pane = $self->{active_pane};
    my $opposite_pane = $self->{opposite_pane};

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
        await $self->{on_confirm}->($message, 'Confirm');
        await $self->_perform_future($opposite_pane, $files);
    }
    catch ($e) {
        return if $self->_is_cancelled($e);
        await $self->{on_alert}->("Failed to copy:\n- (copy): $e", 'Error');
    }
}

sub _guard_same_directory($self, $src_pane, $dest_pane) {
    my $src_path = $src_pane->current_path;
    my $dest_path = $dest_pane->current_path;

    if ($src_path->stringify eq $dest_path->stringify) {
        $self->{on_status_change}->("Copy skipped: source and destination are the same");
        return true;
    }

    return false;
}

sub _guard_copy_into_self($self, $files, $dest_pane) {
    my $dest_path = $dest_pane->current_path;

    if (DoubleDrive::FileManipulator->copy_into_self($files, $dest_path)) {
        $self->{on_status_change}->("Copy skipped: destination is inside source");
        return true;
    }

    return false;
}

sub _build_message($self, $files, $existing) {
    my $count = scalar(@$files);
    my $file_list = join(", ", map { display_name($_->basename) } @$files);
    my $existing_list = join(", ", map { display_name($_) } @$existing);

    if ($count == 1) {
        return "Overwrite $existing_list?";
    }

    my $existing_count = scalar(@$existing);
    return "Copy $count files ($file_list)?\n$existing_count file(s) will be overwritten: $existing_list";
}

sub _is_cancelled($self, $e) {
    # When await sees a failed Future, it throws the failure's first arg as an exception.
    # We treat anything beginning with "cancelled" as a user cancel.
    return "$e" =~ /^cancelled\b/;
}

async sub _perform_future($self, $dest_pane, $files) {
    my $dest_path = $dest_pane->current_path;
    my $failed = DoubleDrive::FileManipulator->copy_files($files, $dest_path);

    # Reload destination pane directory
    $dest_pane->reload_directory();

    if (@$failed) {
        my $error_msg = "Failed to copy:\n" .
            join("\n", map { "- " . display_name($_->{file}) . ": $_->{error}" } @$failed);
        await $self->{on_alert}->($error_msg, 'Error');
    }
}
