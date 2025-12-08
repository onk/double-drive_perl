use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Archive::Reader {
    # Abstract base class for reading archive files
    # Implementations must provide:
    # - list_entries($internal_path) : arrayref of entry hashes
    # - get_entry_info($internal_path) : entry hash or undef

    field $archive_path :param :reader;

    method list_entries ($internal_path) {
        die "Subclass must implement list_entries()";
    }

    method get_entry_info ($internal_path) {
        die "Subclass must implement get_entry_info()";
    }
}
