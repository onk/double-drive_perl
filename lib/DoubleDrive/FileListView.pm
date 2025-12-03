package DoubleDrive::FileListView;
use v5.42;
use utf8;
use parent 'Tickit::Widget::Static';

use Tickit::Pen;
use constant HIGHLIGHT_PEN => Tickit::Pen->new(fg => "hi-yellow");

# Request minimal width - this allows HBox to distribute width evenly
sub cols ($self) { 1 }

sub new ($class, @args) {
    my $self = $class->SUPER::new(@args);
    $self->{lines} = [];
    return $self;
}

# Accept rows with metadata and format them into displayable lines.
# Row shape: { item => FileListItem, is_cursor => Bool }
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
        my $item = $row->{item};

        my $selector = $item->is_selected
            ? ($row->{is_cursor} ? ">*" : " *")
            : ($row->{is_cursor} ? "> " : "  ");

        my $formatted_name = $item->format_name($max_name_width);
        my $size = $item->format_size;
        my $mtime = $item->format_mtime;

        my $text;
        if (defined $size && defined $mtime) {
            $text = $selector . $formatted_name . " " . $size . "  " . $mtime;
        } else {
            $text = $selector . $formatted_name;
        }

        my $pen = $item->is_match ? HIGHLIGHT_PEN : undef;
        push @$lines, { text => $text, pen => $pen };
    }

    return $lines;
}

sub _max_name_width ($self, $width) {
    my $max_name_width = $width - 2 - 8 - 3 - 11;
    $max_name_width = 10 if $max_name_width < 10;    # Minimum width
    return $max_name_width;
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
