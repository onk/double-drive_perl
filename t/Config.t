use v5.42;
use utf8;
use lib 'lib';

use Test2::V0;
use Path::Tiny qw(path tempdir);
use JSON::PP qw(encode_json);
use DoubleDrive::Config;

sub with_config_home ($code) {
    my $tmp = tempdir;
    local $ENV{XDG_CONFIG_HOME} = $tmp;
    $code->($tmp);
}

subtest 'load registered directories from XDG_CONFIG_HOME' => sub {
    with_config_home sub ($config_home) {
        my $config_file = path($config_home, 'double_drive', 'config.json');
        $config_file->parent->mkpath;

        my $payload = {
            registered_directories => [
                { name => 'home', path => '/home/user', key => 'h' },
                { name => 'tmp',  path => '/tmp',        key => 't' },
                { name => 'log',  path => '/var/log',    key => 'l' },
            ],
        };
        $config_file->spew_utf8(encode_json($payload));

        my $config = DoubleDrive::Config->new;
        my $dirs = $config->load_registered_directories();
        is $dirs, [
            { name => 'home', path => '/home/user', key => 'h' },
            { name => 'tmp',  path => '/tmp',        key => 't' },
            { name => 'log',  path => '/var/log',    key => 'l' },
        ], 'registered directories parsed';
    };
};

subtest 'missing or invalid config yields empty list' => sub {
    with_config_home sub ($config_home) {
        my $config = DoubleDrive::Config->new;
        my $dirs = $config->load_registered_directories();
        is $dirs, [], 'missing file returns empty arrayref';

        my $config_file = path($config_home, 'double_drive', 'config.json');
        $config_file->parent->mkpath;
        $config_file->spew_utf8('{bad json');

        my $broken = $config->load_registered_directories();
        is $broken, [], 'invalid json returns empty arrayref';
    };
};

done_testing;
