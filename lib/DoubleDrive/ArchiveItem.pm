use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::ArchiveItem :isa(DoubleDrive::BaseListItem) {
    use Unicode::Normalize qw(NFC);
    use Encode qw(decode_utf8);
    use Path::Tiny ();
    use DoubleDrive::ArchiveItem::Stat;
    use DoubleDrive::Archive::ReaderFactory;
    use DoubleDrive::FileListItem;

    # Represents items inside archives
    # Inherits from BaseListItem for common formatting methods

    field $archive_path :param;            # Real filesystem path to .zip file
    field $internal_path :param = '';      # Path inside archive (empty for root)
    field $entry_info :param = undef;      # Hash with {is_dir, size, mtime, basename}
    field $reader :param = undef;          # Shared Archive::Reader instance (reused to avoid re-reading ZIP file)

    # Constructor for archive root
    sub new_from_archive ($class, $file_item) {
        my $reader = DoubleDrive::Archive::ReaderFactory->create($file_item->path)
            or die "Unsupported or corrupted archive";

        return $class->new(
            archive_path => $file_item->path,
            reader => $reader,
        );
    }

    method basename() {
        if (defined $entry_info) {
            return $entry_info->{basename};  # Already NFC normalized by Archive::Reader
        } else {
            # Archive root
            return NFC(decode_utf8($archive_path->basename));
        }
    }

    method stringify() {
        if (defined $entry_info) {
            return NFC(decode_utf8("$archive_path") . "::$internal_path");
        } else {
            # Archive root
            return NFC(decode_utf8("$archive_path") . "::");
        }
    }

    method is_dir() {
        return defined $entry_info ? $entry_info->{is_dir} : true;  # Root is directory
    }

    method is_archive() {
        return false;  # Prevents nested archive navigation
    }

    method is_archive_root() {
        return $internal_path eq '';
    }

    method children() {
        my $entries = $reader->list_entries($internal_path);

        return [
            map {
                DoubleDrive::ArchiveItem->new(
                    archive_path  => $archive_path,
                    internal_path => $_->{path},
                    entry_info    => $_,
                    reader        => $reader,
                )
            } @$entries
        ];
    }

    method stat() {
        return undef unless defined $entry_info;

        return DoubleDrive::ArchiveItem::Stat->new(
            size_value  => $entry_info->{size},
            mtime_value => $entry_info->{mtime},
            mode_value  => $entry_info->{mode},
        );
    }

    method parent() {
        if ($self->is_archive_root) {
            # Return the parent directory of the archive file
            return DoubleDrive::FileListItem->new(path => $archive_path->parent);
        }

        # Find parent path by removing last component
        my $path_parts = [split '/', $internal_path];
        my $parent_path = join('/', @$path_parts[0..$#$path_parts-1]);

        if ($parent_path eq '') {
            # Parent is archive root
            return DoubleDrive::ArchiveItem->new(
                archive_path => $archive_path,
                reader       => $reader,
            );
        }

        # Parent is another directory in archive
        my $parent_info = $reader->get_entry_info($parent_path);

        return DoubleDrive::ArchiveItem->new(
            archive_path  => $archive_path,
            internal_path => $parent_path,
            entry_info    => $parent_info,
            reader        => $reader,
        );
    }
}
