use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Archive::ReaderFactory {
    use DoubleDrive::Archive::Reader::Zip;

    sub create ($class, $archive_path) {
        my $filename = lc($archive_path->basename);

        # Only support ZIP format
        return unless $filename =~ /\.zip$/;

        try {
            return DoubleDrive::Archive::Reader::Zip->new(archive_path => $archive_path);
        } catch ($e) {
            return undef;
        }
    }
}
