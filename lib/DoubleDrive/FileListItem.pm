use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::FileListItem :isa(DoubleDrive::BaseListItem) {
    use Encode qw(decode_utf8);
    use Unicode::Normalize qw(NFC);

    field $path :param :reader;
    field $basename :reader;     # NFC normalized
    field $stringify :reader;    # NFC normalized

    ADJUST {
        # Path::Tiny returns UTF-8 byte strings, convert to internal strings
        $basename = NFC(decode_utf8($path->basename));
        $stringify = NFC(decode_utf8($path->stringify));
    }

    method is_dir() { $path->is_dir }

    method is_archive() {
        return false if $self->is_dir;
        my $name = lc($basename);
        return $name =~ /\.zip$/;
    }

    method stat() {
        try {
            $path->stat
        } catch($e) {
            return undef;
        }
    }

    method children() {
        return [map { DoubleDrive::FileListItem->new(path => $_) } $path->children];
    }

    method parent() {
        return DoubleDrive::FileListItem->new(path => $path->parent);
    }

    method realpath() {
        return DoubleDrive::FileListItem->new(path => $path->realpath);
    }
}
