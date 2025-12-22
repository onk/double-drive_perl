use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::ArchiveItem::Stat {
    # Mock stat object for archive entries
    # Provides size() and mtime() methods compatible with File::stat

    field $size_value :param :reader(size);
    field $mtime_value :param :reader(mtime);
    field $mode_value :param :reader(mode) = undef;
}
