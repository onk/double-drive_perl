use v5.42;
use utf8;
use experimental 'class', 'defer';

class DoubleDrive::Command::Rename {
    use Cwd qw(getcwd);

    field $context :param;
    field $external_command_runner :param;

    field $active_pane;
    field $on_status_change;

    ADJUST {
        $active_pane = $context->active_pane;
        $on_status_change = $context->on_status_change;
    }

    method execute() {
        my $file_items = $active_pane->get_files_to_operate();
        return unless @$file_items;

        my $basenames = [ map { $_->basename } @$file_items ];

        # Change to current directory
        my $target_dir = $active_pane->current_path->stringify;
        my $orig_dir = getcwd();
        chdir $target_dir;
        defer { chdir $orig_dir; }

        # Transfer terminal control to mmv
        my $exit_code = $external_command_runner->('mmv', @$basenames);

        # Reload directory and clear selection
        $active_pane->reload_directory();
        $active_pane->clear_selection();

        if ($exit_code != 0) {
            $on_status_change->("mmv exited with code: $exit_code");
        }
    }
}
