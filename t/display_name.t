use v5.42;
use utf8;

use Test2::V0;
use Encode qw(encode);
use Unicode::Normalize qw(NFD);

use lib 'lib';
use DoubleDrive::TextUtil qw(display_name);

subtest 'decodes utf8 bytes to characters' => sub {
    my $bytes = pack('C*', 0x63, 0x61, 0x66, 0xc3, 0xa9);  # caf\xc3\xa9
    is display_name($bytes), "café", 'bytes decoded to characters';
};

subtest 'normalizes to NFC' => sub {
    my $nfd_bytes = encode('utf8', NFD("é"));
    is display_name($nfd_bytes), "é", 'NFD input normalized to NFC';
};

done_testing;
