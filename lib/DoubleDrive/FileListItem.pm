use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::FileListItem {
    use Encode qw(decode_utf8);
    use Unicode::Normalize qw(NFC);

    field $path :param :reader;
    field $basename :reader;     # NFC normalized
    field $stringify :reader;    # NFC normalized
    field $is_selected :reader = false;
    field $is_match :reader = false;

    ADJUST {
        # Path::Tiny returns UTF-8 byte strings, convert to internal strings
        $basename = NFC(decode_utf8($path->basename));
        $stringify = NFC(decode_utf8($path->stringify));
    }

    method is_dir() { $path->is_dir }
    method stat() { $path->stat }

    method set_match($match) {
        $is_match = $match;
    }

    method toggle_selected() {
        $is_selected = !$is_selected;
    }
}
