use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Config {
    use Path::Tiny qw(path);
    use JSON::PP;

    field $config_file;

    ADJUST {
        my $config_home = $ENV{XDG_CONFIG_HOME} // path("~/.config")->absolute->stringify;
        $config_file = path($config_home)->child('double_drive', 'config.json');
    }

    method load_registered_directories() {
        return [] unless $config_file->is_file;

        my $data;
        try {
            my $content = $config_file->slurp_utf8;
            $data = decode_json($content);
        } catch ($e) {
            return [];
        }

        return [] unless ref $data eq 'HASH';

        my $entries = $data->{registered_directories} // [];
        return [] unless ref $entries eq 'ARRAY';
        return $entries;
    }
}
