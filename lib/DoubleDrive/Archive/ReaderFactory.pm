use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Archive::ReaderFactory {
    use DoubleDrive::Archive::Reader::Zip;
    use DoubleDrive::Archive::Reader::TarGz;

    sub create ($class, $archive_path) {
        my $filename = lc($archive_path->basename);

        # Support ZIP, tar.gz, and tgz formats
        if ($filename =~ /\.zip$/) {
            try {
                return DoubleDrive::Archive::Reader::Zip->new(archive_path => $archive_path);
            } catch ($e) {
                return undef;
            }
        } elsif ($filename =~ /\.(tar\.gz|tgz)$/) {
            try {
                return DoubleDrive::Archive::Reader::TarGz->new(archive_path => $archive_path);
            } catch ($e) {
                return undef;
            }
        }

        return undef;
    }
}
