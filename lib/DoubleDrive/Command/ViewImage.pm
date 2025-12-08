use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Command::ViewImage {
    use Future;

    field $context :param;
    field $tickit :param;
    field $is_left :param;
    field $dialog_scope :param;

    field $active_pane;
    field $on_status_change;

    ADJUST {
        $active_pane = $context->active_pane;
        $on_status_change = $context->on_status_change;
    }

    method execute() {
        my $files = $active_pane->get_files_to_operate();
        return unless @$files;
        my $file = $files->[0];
        my $path = $file->stringify;

        return unless $path =~ /\.(?:jpe?g|png|gif|bmp|tiff?|webp|svg|heic)$/i;

        my ($rows, $cols) = $tickit->term->get_size;

        # Ensure running inside kitty terminal
        unless ($ENV{KITTY_WINDOW_ID} || (($ENV{TERM} // '') =~ /kitty/)) {
            $on_status_change->('Image preview requires kitty terminal');
            return;
        }

        my $place = $self->_compute_place($rows, $cols, $is_left);
        return unless $place;

        $active_pane->start_preview();
        my $ret = system('kitty', '+kitten', 'icat', '--place', $place, $path);
        my $exit_code = $ret >> 8;
        if ($exit_code != 0) {
            $on_status_change->("Failed to show image (exit code $exit_code)");
            $active_pane->stop_preview();
            return;
        }

        # Copy to lexical variable so closure can trigger DESTROY by setting undef
        my $scope = $dialog_scope;

        my $close_image = sub {
            system('kitty', '+kitten', 'icat', '--clear');
            $active_pane->stop_preview();
            $scope = undef;
        };

        $on_status_change->("Viewing image - press v/Enter/Escape to close");

        $scope->bind('v' => $close_image);
        $scope->bind('Enter' => $close_image);
        $scope->bind('Escape' => $close_image);

        return;
    }

    method _compute_place($rows, $cols, $is_left) {
        my $spacing = 1;
        my $status_height = 1;
        my $pane_cols = int(($cols - $spacing) / 2);
        my $pane_rows = $rows - $status_height;

        return undef unless $pane_cols > 0 && $pane_rows > 0;

        my $x_cell = $is_left ? 0 : ($pane_cols + $spacing);
        my $y_cell = 0;

        my $inner_cols = $pane_cols - 2;
        my $inner_rows = $pane_rows - 2;
        return undef unless $inner_cols > 0 && $inner_rows > 0;

        my $place_x = $x_cell + 1;
        my $place_y = $y_cell + 1;

        return sprintf("%dx%d@%dx%d", $inner_cols, $inner_rows, $place_x, $place_y);
    }
}
