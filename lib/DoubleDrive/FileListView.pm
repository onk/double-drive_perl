package DoubleDrive::FileListView;
use v5.42;
use utf8;
use parent 'Tickit::Widget::Static';

use DoubleDrive::TextUtil qw(display_name);
use Tickit::Pen;
use POSIX qw(strftime);
use Unicode::GCString;
use constant HIGHLIGHT_PEN => Tickit::Pen->new(fg => "hi-yellow");

# Request minimal width - this allows HBox to distribute width evenly
sub cols ($self) { 1 }

sub new ($class, @args) {
    my $self = $class->SUPER::new(@args);
    $self->{lines} = [];
    return $self;
}

# Accept rows with metadata and format them into displayable lines.
# Row shape: { path => Path::Tiny, is_cursor => Bool, is_selected => Bool, is_match => Bool }
sub set_rows ($self, $rows) {
    my $window = $self->window;
    my $cols   = $window ? $window->cols : undef;

    my $lines = $self->_rows_to_lines($rows, $cols);

    $self->{lines} = $lines;
    $self->redraw if $window;
    return $self;
}

sub _rows_to_lines ($self, $rows, $cols) {

    $rows //= [];
    return [{ text => "(empty directory)" }] unless @$rows;

    my $max_name_width = defined $cols ? $self->_max_name_width($cols) : 10;
    my $lines          = [];

    for my $row (@$rows) {
        my $file = $row->{path};
        my $name = display_name($file->basename);
        $name .= "/" if $file->is_dir;

        my $selector = $row->{is_selected}
            ? ($row->{is_cursor} ? ">*" : " *")
            : ($row->{is_cursor} ? "> " : "  ");

        my $stat = $file->stat;
        my $text;
        if ($stat) {
            my $size = $self->_format_size($stat->size);
            my $mtime = $self->_format_mtime($stat->mtime);
            my $formatted_name = $self->_format_name($name, $max_name_width);
            $text = $selector . $formatted_name . " " . $size . "  " . $mtime;
        } else {
            my $formatted_name = $self->_format_name($name, $max_name_width);
            $text = $selector . $formatted_name;
        }

        my $pen = $row->{is_match} ? HIGHLIGHT_PEN : undef;
        push @$lines, { text => $text, pen => $pen };
    }

    return $lines;
}

sub _max_name_width ($self, $width) {
    my $max_name_width = $width - 2 - 8 - 3 - 11;
    $max_name_width = 10 if $max_name_width < 10;    # Minimum width
    return $max_name_width;
}

sub _format_size ($self, $bytes) {
    my $units = [qw(B K M G T)];
    my $unit_index = 0;
    my $size = $bytes;

    while ($size >= 1024 && $unit_index < $#$units) {
        $size /= 1024;
        $unit_index++;
    }

    return sprintf("%6.1f%s", $size, $units->[$unit_index]);
}

sub _format_mtime ($self, $mtime) {
    my $one_year_ago = time() - (365 * 24 * 60 * 60);

    if ($mtime > $one_year_ago) {
        return strftime("%m/%d %H:%M", localtime($mtime));
    } else {
        return strftime("%Y-%m-%d", localtime($mtime));
    }
}

sub _format_name ($self, $str, $target_width) {
    my $gc = Unicode::GCString->new($str);
    my $str_width = $gc->columns;

    if ($str_width <= $target_width) {
        return $str . (' ' x ($target_width - $str_width));
    }

    my $ellipsis = "...";
    my $ellipsis_width = 3;
    my $truncate_limit = $target_width - $ellipsis_width;
    return $ellipsis if $truncate_limit <= 0;

    my $out = "";
    my $used_width = 0;
    for my $g ($str =~ /\X/g) {
        my $w = Unicode::GCString->new($g)->columns;
        last if $used_width + $w > $truncate_limit;
        $out .= $g;
        $used_width += $w;
    }

    my $padding = $target_width - ($used_width + $ellipsis_width);
    $padding = 0 if $padding < 0;
    return $out . $ellipsis . (' ' x $padding);
}

sub render_to_rb ($self, $rb, $rect) {

    $rb->eraserect($rect);

    my $lines = $self->{lines} || [];
    my $start_line = $rect->top;
    my $end_line = $rect->bottom - 1;

    for my $i ($start_line .. $end_line) {
        last if $i >= @$lines;

        my $line = $lines->[$i];
        my $text = $line->{text} || "";
        my $pen = $line->{pen};

        if (defined $pen) {
            $rb->text_at($i, 0, $text, $pen);
        } else {
            $rb->text_at($i, 0, $text);
        }
    }
}
