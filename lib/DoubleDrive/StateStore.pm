use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::StateStore {
    use Path::Tiny qw(path);
    use JSON::PP;

    field $state_file;

    ADJUST {
        my $state_home = $ENV{XDG_STATE_HOME} // path("~/.local/state")->absolute->stringify;
        $state_file = path($state_home)->child('double_drive', 'state.json');
    }

    method load_paths() {
        return {} unless $state_file->is_file;

        my $data;
        try {
            my $content = $state_file->slurp_utf8;
            $data = decode_json($content);
        } catch($e) {
            return {};
        }
        return {} unless ref $data eq 'HASH';

        return {
            left_path => $data->{left_path},
            right_path => $data->{right_path},
        };
    }

    method save_paths($left_path, $right_path) {
        my $dir = $state_file->parent;
        $dir->mkpath unless $dir->is_dir;
        return unless $dir->is_dir;

        my $json = JSON::PP->new->utf8->pretty->canonical;
        my $payload = $json->encode({
            left_path => $left_path,
            right_path => $right_path,
        });

        $state_file->spew_utf8($payload);
    }
}
