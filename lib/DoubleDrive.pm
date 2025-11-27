use v5.42;
use experimental 'class';

use Tickit;
use Tickit::Widget::HBox;
use Tickit::Widget::Frame;
use Tickit::Widget::Static;

class DoubleDrive {
    field $tickit;

    ADJUST {
        $self->_build_ui();
    }

    method _build_ui() {
        my $hbox = Tickit::Widget::HBox->new(spacing => 1);

        my $left = Tickit::Widget::Frame->new(
            style => { linetype => "single" },
        )->set_child(Tickit::Widget::Static->new(text => "Left Pane"));

        my $right = Tickit::Widget::Frame->new(
            style => { linetype => "single" },
        )->set_child(Tickit::Widget::Static->new(text => "Right Pane"));

        $hbox->add($left, expand => 1);
        $hbox->add($right, expand => 1);

        $tickit = Tickit->new(root => $hbox);
    }

    method run() {
        $tickit->run;
    }
}
