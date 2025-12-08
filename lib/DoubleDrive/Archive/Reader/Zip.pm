use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Archive::Reader::Zip :isa(DoubleDrive::Archive::Reader) {
    use Archive::Zip qw(:ERROR_CODES);
    use Unicode::Normalize qw(NFC);
    use Encode qw(decode_utf8);

    field $zip;

    ADJUST {
        $zip = Archive::Zip->new();
        my $status = $zip->read($self->archive_path->stringify);
        die "Failed to read ZIP archive: " . $self->archive_path unless $status == AZ_OK;
    }

    method list_entries ($internal_path = '') {
        my $prefix = $internal_path eq '' ? '' : "$internal_path/";
        my $entries = {};

        for my $member ($zip->members) {
            my $filename = $member->fileName;
            # Archive::Zip may return already-decoded strings, handle both cases
            my $full_name = utf8::is_utf8($filename) ? $filename : decode_utf8($filename);
            $full_name = NFC($full_name);  # Normalize to NFC
            $full_name =~ s{^/+}{};  # Remove leading slashes

            # Skip if not under the requested path
            next unless $full_name =~ /^\Q$prefix\E/;

            # Get the relative path after the prefix
            my $relative = substr($full_name, length($prefix));
            next if $relative eq '';  # Skip the directory itself

            # Check if this is a direct child
            my ($basename, $rest) = split '/', $relative, 2;

            if (defined $rest && $rest ne '') {
                # This is a nested item, so we have an intermediate directory
                # Add implicit directory only if not exists (explicit entries have priority)
                $entries->{$basename} //= {
                    path     => $internal_path eq '' ? $basename : "$internal_path/$basename",
                    is_dir   => true,
                    size     => 0,
                    mtime    => time,  # Use current time for implicit directories
                    basename => $basename,
                };
            } else {
                # This is a direct child (explicit entry)
                my $is_dir = $full_name =~ m{/$};

                $entries->{$basename} = {
                    path       => $internal_path eq '' ? $basename : "$internal_path/$basename",
                    is_dir     => $is_dir,
                    size       => $is_dir ? 0 : $member->uncompressedSize,
                    mtime      => $member->lastModTime,
                    basename   => $basename,
                };
            }
        }

        return [values %$entries];
    }

    method get_entry_info ($internal_path) {
        # Normalize internal path
        $internal_path =~ s{^/+}{};  # Remove leading slashes
        $internal_path =~ s{/+$}{};  # Remove trailing slashes

        return undef if $internal_path eq '';  # Archive root has no entry_info

        # Get parent path and basename
        my $path_parts = [split '/', $internal_path];
        my $parent_path = join('/', @$path_parts[0..$#$path_parts-1]);  # '' for root-level entries
        my $basename = $path_parts->[-1];

        # List entries in parent directory (or root) and find the target
        my $entries = $self->list_entries($parent_path);
        my ($entry) = grep { $_->{basename} eq $basename } @$entries;

        return $entry;
    }
}
