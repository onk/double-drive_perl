use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::TextUtil {
    use Exporter 'import';
    use Encode qw(decode_utf8);
    use Unicode::Normalize qw(NFC);

    our @EXPORT_OK = qw(display_name);

    sub display_name ($name) {
        # Path::Tiny gives byte strings; decode to characters, then normalize to NFC
        # so Tickit width accounting stays consistent on platforms (e.g. macOS) that
        # produce NFD filenames.
        return NFC(decode_utf8($name));
    }
}
