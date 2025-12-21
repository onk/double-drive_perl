use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Command::ViewFile {
    use Future;

    field $context :param;
    field $tickit :param;
    field $is_left :param;
    field $dialog_scope :param;

    field $active_pane;
    field $on_status_change;
    field $image_files;
    field $current_index;
    field $place;

    ADJUST {
        $active_pane = $context->active_pane;
        $on_status_change = $context->on_status_change;
    }

    method execute() {
        my $files = $active_pane->get_files_to_operate();
        return unless @$files;

        my $file = $files->[0];
        unless ($file->stringify =~ /\.(?:jpe?g|png|gif|bmp|tiff?|webp|svg|heic)$/i) {
            # View PDF files
            return $self->_view_pdf($file) if $file->stringify =~ /\.pdf$/i;

            # Common binary formats that might pass -T check or shouldn't be opened as text
            return if $file->stringify =~ /\.(?:zip|gz|tar|rar|7z|iso|dmg|exe|jar)$/i;
            return unless -T $file->stringify;
            return $self->_view_text($file);
        }

        # Filter image files
        $image_files = [ grep {
            $_->stringify =~ /\.(?:jpe?g|png|gif|bmp|tiff?|webp|svg|heic)$/i
        } @$files ];
        return unless @$image_files;

        my ($rows, $cols) = $tickit->term->get_size;

        # Ensure running inside kitty terminal
        unless ($ENV{KITTY_WINDOW_ID} || (($ENV{TERM} // '') =~ /kitty/)) {
            $on_status_change->('Image preview requires kitty terminal');
            return;
        }

        $place = $self->_compute_place($rows, $cols, $is_left);
        return unless $place;

        $active_pane->start_preview();

        $current_index = 0;

        try {
            $self->_show_image();
        }
        catch ($e) {
            $self->_clear_image();
            $active_pane->stop_preview();
            $on_status_change->($e);
            return;
        }

        $dialog_scope->bind('v' => sub { $self->_close() });
        $dialog_scope->bind('Enter' => sub { $self->_close() });
        $dialog_scope->bind('Escape' => sub { $self->_close() });
        $dialog_scope->bind('j' => sub { $self->_next_image() });
        $dialog_scope->bind('k' => sub { $self->_prev_image() });
        $dialog_scope->bind('Down' => sub { $self->_next_image() });
        $dialog_scope->bind('Up' => sub { $self->_prev_image() });

        return;
    }

    method _clear_image() {
        system('kitty', '+kitten', 'icat', '--clear');
    }

    method _show_image() {
        my $path = $image_files->[$current_index]->stringify;
        system('kitty', '+kitten', 'icat', '--place', $place, $path);
        my $exit_code = $? >> 8;

        if ($exit_code != 0) {
            die "Failed to show image (exit code $exit_code)";
        }
        my $total = scalar @$image_files;
        if ($total > 1) {
            my $pos = $current_index + 1;
            $on_status_change->("[$pos/$total] $path");
        } else {
            $on_status_change->("$path");
        }
    }

    method _close() {
        if ($image_files) {
            $self->_clear_image();
        }
        $active_pane->stop_preview();
        $dialog_scope = undef;
    }

    method _next_image() {
        return if @$image_files == 1;
        $self->_clear_image();
        $current_index = ($current_index + 1) % @$image_files;
        try {
            $self->_show_image();
        }
        catch ($e) {
            $on_status_change->($e);
            $self->_close();
        }
    }

    method _prev_image() {
        return if @$image_files == 1;
        $self->_clear_image();
        $current_index = ($current_index - 1) % @$image_files;
        try {
            $self->_show_image();
        }
        catch ($e) {
            $on_status_change->($e);
            $self->_close();
        }
    }

    method _view_text($file) {
        $tickit->term->pause;
        system('bat', '--paging=always', '--pager=less -R +Gg', $file->stringify);
        $tickit->term->resume;
        $tickit->rootwin->expose;

        $self->_close();
    }

    method _view_pdf($file) {
        # quotemeta escapes special shell characters to prevent shell injection
        my $pdf_path = quotemeta($file->stringify);

        $tickit->term->pause;
        # Use shell for piping (IPC::Open2 would be complex; temp files add I/O overhead)
        # quotemeta makes this safe from shell injection
        system("pdftotext -layout $pdf_path - 2>&1 | bat --paging=always --pager='less -R +Gg' --language=txt");
        my $exit_code = $? >> 8;

        $tickit->term->resume;
        $tickit->rootwin->expose;

        $self->_close();

        if ($exit_code != 0) {
            $on_status_change->("Failed to view PDF (exit code: $exit_code)");
        }
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
