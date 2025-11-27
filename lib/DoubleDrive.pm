use v5.42;
use experimental 'class';

use Tickit;
use Tickit::Widget::HBox;
use DoubleDrive::Pane;

class DoubleDrive {
    field $tickit;

    ADJUST {
        $self->_build_ui();
    }

    method _build_ui() {
        my $hbox = Tickit::Widget::HBox->new(spacing => 1);

        my $left = DoubleDrive::Pane->new(current_path => '.');
        my $right = DoubleDrive::Pane->new(current_path => '.');

        $hbox->add($left->widget, expand => 1);
        $hbox->add($right->widget, expand => 1);

        $tickit = Tickit->new(root => $hbox);
    }

    method run() {
        $tickit->run;
    }
}
