use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Command::MakeDir {
    use Path::Tiny;
    use Encode qw(encode_utf8);

    field $context :param;
    field $cmdline_mode :param;
    field $active_pane;
    field $on_status_change;

    ADJUST {
        $active_pane = $context->active_pane;
        $on_status_change = $context->on_status_change;
    }

    method execute() {
        # Enter command line mode to get directory name
        $cmdline_mode->enter({
            on_init => sub {
                $on_status_change->("Create directory: ");
            },
            on_change => sub ($dirname) {
                $on_status_change->("Create directory: $dirname");
            },
            on_execute => sub ($dirname) {
                $self->_create_directory($dirname);
            },
            on_cancel => sub {
                $active_pane->_render();
            }
        });
    }

    method _create_directory($dirname) {
        # Validate directory name
        if ($dirname eq '') {
            $on_status_change->("Directory name cannot be empty");
            return;
        }

        if ($dirname =~ m{/}) {
            $on_status_change->("Directory name cannot contain '/'");
            return;
        }

        my $current_item = $active_pane->current_path;
        my $current_path = $current_item->path;
        my $new_dir_path = $current_path->child(encode_utf8($dirname));

        if ($new_dir_path->exists) {
            $on_status_change->("Directory '$dirname' already exists");
            return;
        }

        try {
            $new_dir_path->mkpath;
            $active_pane->change_directory($new_dir_path->stringify);
        }
        catch ($e) {
            $on_status_change->("Failed to create directory: $e");
        }
    }
}
