use v5.42;
use utf8;
use lib 'lib';

use Test2::V0;
use Path::Tiny qw(path tempdir);
use JSON::PP qw(decode_json);
use DoubleDrive::StateStore;

sub with_state_home ($code) {
    my $tmp = tempdir;
    local $ENV{XDG_STATE_HOME} = $tmp;
    $code->($tmp);
}

subtest 'save then load uses XDG_STATE_HOME' => sub {
    with_state_home sub ($state_home) {
        my $left = '/tmp/left';
        my $right = '/tmp/right';

        my $store = DoubleDrive::StateStore->new;
        $store->save_paths($left, $right);

        my $state_file = path($state_home, 'double_drive', 'state.json');
        ok $state_file->is_file, 'state file created';

        my $raw = decode_json($state_file->slurp_utf8);
        is $raw->{left_path}, $left, 'left path saved';
        is $raw->{right_path}, $right, 'right path saved';

        my $loaded = $store->load_paths();
        is $loaded, { left_path => $left, right_path => $right }, 'load returns saved paths';
    };
};

subtest 'missing file returns empty hashref' => sub {
    with_state_home sub {
        my $store = DoubleDrive::StateStore->new;
        my $loaded = $store->load_paths();
        is $loaded, {}, 'no file yields empty hashref';
    };
};

subtest 'malformed json returns empty hashref' => sub {
    with_state_home sub ($state_home) {
        my $state_file = path($state_home, 'double_drive', 'state.json');
        $state_file->parent->mkpath;
        $state_file->spew_utf8('{bad json');

        my $store = DoubleDrive::StateStore->new;
        my $loaded = $store->load_paths();
        is $loaded, {}, 'invalid json yields empty hashref';
    };
};

done_testing;
