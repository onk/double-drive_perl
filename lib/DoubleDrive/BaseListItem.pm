use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::BaseListItem {
    use POSIX qw(strftime);
    use Unicode::GCString;

    field $is_selected :reader = false;
    field $is_match :reader = false;

    # Abstract methods - must be implemented by subclasses
    method basename() { die "Subclass must implement basename()" }
    method stringify() { die "Subclass must implement stringify()" }
    method is_dir() { die "Subclass must implement is_dir()" }
    method stat() { die "Subclass must implement stat()" }
    method children() { die "Subclass must implement children()" }

    # Note: path() is NOT part of the base interface
    # FileListItem has path() for real filesystem operations
    # ArchiveItem does NOT have path() as it represents virtual paths

    # Common implementations
    method size() {
        my $stat = $self->stat;
        return $stat ? $stat->size : 0;
    }

    method mtime() {
        my $stat = $self->stat;
        return $stat ? $stat->mtime : 0;
    }

    method set_match($match) {
        $is_match = $match;
    }

    method toggle_selected() {
        $is_selected = !$is_selected;
    }

    method extname() {
        my $name = $self->basename;

        # Special cases: . and .. have no extension
        return "" if $name eq '.' || $name eq '..';

        # Check if it's a dotfile without extension: starts with dot, no other dots
        if ($name =~ /^\./ && $name !~ /\..*\./) {
            return "";
        }

        # Match last dot + extension (including empty extension for trailing dot)
        if ($name =~ /(\.[^.]*)$/) {
            return $1;
        }

        return "";
    }

    method format_size() {
        my $stat = $self->stat;
        return undef unless $stat;

        my $bytes = $stat->size;
        my $units = [qw(B K M G T)];
        my $unit_index = 0;
        my $size = $bytes;

        while ($size >= 1024 && $unit_index < $#$units) {
            $size /= 1024;
            $unit_index++;
        }

        return sprintf("%6.1f%s", $size, $units->[$unit_index]);
    }

    method format_mtime() {
        my $stat = $self->stat;
        return undef unless $stat;

        my $mtime = $stat->mtime;
        my $one_year_ago = time() - (365 * 24 * 60 * 60);

        if ($mtime > $one_year_ago) {
            return strftime("%m/%d %H:%M", localtime($mtime));
        } else {
            return strftime("%Y-%m-%d", localtime($mtime));
        }
    }

    method format_name($target_width) {
        my $name = $self->basename;
        $name .= "/" if $self->is_dir;

        my $gc = Unicode::GCString->new($name);
        my $str_width = $gc->columns;

        if ($str_width <= $target_width) {
            return $name . (' ' x ($target_width - $str_width));
        }

        my $ellipsis = "...";
        my $ellipsis_width = 3;
        my $truncate_limit = $target_width - $ellipsis_width;
        return $ellipsis if $truncate_limit <= 0;

        my $out = "";
        my $used_width = 0;
        for my $g ($name =~ /\X/g) {
            my $w = Unicode::GCString->new($g)->columns;
            last if $used_width + $w > $truncate_limit;
            $out .= $g;
            $used_width += $w;
        }

        my $padding = $target_width - ($used_width + $ellipsis_width);
        $padding = 0 if $padding < 0;
        return $out . $ellipsis . (' ' x $padding);
    }
}
