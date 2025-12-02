package DoubleDrive::Command::Delete;
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
    my $files = $self->{active_pane}->get_files_to_operate();
    return unless @$files;

    my $message = $self->_build_message($files);
    try {
        await $self->{on_confirm}->($message, 'Confirm');
        await $self->_perform_future($files);
    }
    catch ($e) {
        return if $self->_is_cancelled($e);
        await $self->{on_alert}->("Failed to delete:\n- (delete): $e", 'Error');
    }
}

sub _build_message($self, $files) {
    my $count = scalar(@$files);
    my $file_list = join(", ", map { display_name($_->basename) } @$files);
    return $count == 1
        ? "Delete $file_list?"
        : "Delete $count files ($file_list)?";
}

sub _is_cancelled($self, $e) {
    # When await sees a failed Future, it throws the failure's first arg as an exception.
    # We treat anything beginning with "cancelled" as a user cancel.
    return "$e" =~ /^cancelled\b/;
}

async sub _perform_future($self, $files) {
    my $failed = DoubleDrive::FileManipulator->delete_files($files);

    # Reload directory after deletion
    $self->{active_pane}->reload_directory();

    if (@$failed) {
        my $error_msg = "Failed to delete:\n" .
            join("\n", map { "- " . display_name($_->{file}) . ": $_->{error}" } @$failed);
        await $self->{on_alert}->($error_msg, 'Error');
    }
}
