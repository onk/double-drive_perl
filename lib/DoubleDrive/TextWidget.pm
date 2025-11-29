use v5.42;

package DoubleDrive::TextWidget;
use parent 'Tickit::Widget::Static';

# Request minimal width - this allows HBox to distribute width evenly
sub cols { 1 }

# Override constructor to add lines field
sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->{lines} = [];
    return $self;
}

# Set lines with optional pens
sub set_lines {
    my ($self, $lines) = @_;
    $self->{lines} = $lines;
    $self->redraw if $self->window;
}

# Override render to support per-line pens
sub render_to_rb {
    my ($self, $rb, $rect) = @_;

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
