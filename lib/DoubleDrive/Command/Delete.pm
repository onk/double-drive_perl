use v5.42;
use experimental 'class';

class DoubleDrive::Command::Delete {
    use DoubleDrive::TextUtil qw(display_name);
    use DoubleDrive::ConfirmDialog;
    use DoubleDrive::AlertDialog;
    use DoubleDrive::FileManipulator;

    method execute($app) {
        my $active_pane = $app->active_pane;
        my $targets = $self->_collect_targets($active_pane) or return;

        my $perform = sub { $self->_perform($app, $active_pane, $targets) };
        my $message = $self->_build_message($targets);
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

    method _build_message($files) {
        my $count = scalar(@$files);
        my $file_list = join(", ", map { display_name($_->basename) } @$files);
        return $count == 1
            ? "Delete $file_list?"
            : "Delete $count files ($file_list)?";
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

    method _perform($app, $pane, $files) {
        my $failed = DoubleDrive::FileManipulator->delete_files($files);

        # Reload directory after deletion
        $pane->reload_directory();

        $self->_alert_errors($app, $failed) if @$failed;
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
