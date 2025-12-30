use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::Dialog::Base {
    use Tickit::Widget::Static;
    use Tickit::Widget::VBox;
    use Tickit::Widget::Frame;
    use Text::Wrap qw(wrap);
    use List::Util qw(min max);

    field $tickit :param :reader;
    field $float_box :param :reader;
    field $key_scope :param;
    field $title :param = 'Dialog';
    field $message :param;
    field $dialog_widget;
    field $float;
    field $instruction_widget;
    field $layout;

    ADJUST {
        $layout = $self->_compute_layout();
        $dialog_widget = $self->_build_widget();
    }

    method _compute_layout() {
        my ($rows, $cols) = (undef, undef);
        if ($tickit && $tickit->can('term') && $tickit->term) {
            ($rows, $cols) = $tickit->term->get_size;
        }

        my $min_width = 30;
        my $fallback_wrap = 80;
        my $base_width = $cols ? $cols - 44 : $fallback_wrap;        # roughly center with margins
        my $max_width = $cols ? max($min_width, $cols - 4) : 120;    # leave a small border

        my $wrap_width = max($min_width, min($base_width, $max_width));
        my $wrapped;
        {
            local $Text::Wrap::columns = $wrap_width;
            $wrapped = wrap("", "", $message // "");
        }

        my $left_margin;
        if ($cols) {
            $left_margin = int(($cols - $wrap_width) / 2);
            $left_margin = max(0, $left_margin);
        } else {
            $left_margin = 10;
        }

        my $top_margin = $rows ? int($rows / 4) : 4;    # near upper third by default

        return {
            text => $wrapped,
            left => $left_margin,
            right => -$left_margin,
            top => $top_margin,
        };
    }

    method _instruction_text() { return "" }

    method _build_widget() {
        my $vbox = Tickit::Widget::VBox->new;

        my $msg_widget = Tickit::Widget::Static->new(
            text => $layout->{text},
            align => "left",
        );

        $instruction_widget = Tickit::Widget::Static->new(
            text => $self->_instruction_text(),
            align => "left",
        );

        $vbox->add($msg_widget, expand => 1);
        $vbox->add($instruction_widget);

        my $frame = Tickit::Widget::Frame->new(
            style => { linetype => "double" },
            title => $title,
        )->set_child($vbox);

        return $frame;
    }

    method _bind_keys() { }    # override in subclasses

    method _update_instruction() {
        $instruction_widget->set_text($self->_instruction_text());
    }

    method show() {
        die "key_scope is required for dialog" unless $key_scope;
        $self->_bind_keys();

        $float = $float_box->add_float(
            child => $dialog_widget,
            top => $layout->{top},
            left => $layout->{left},
            right => $layout->{right},
        );
    }

    method close() {
        $float->remove if $float;
        $key_scope = undef;
    }

    method key_scope() { return $key_scope }
}
