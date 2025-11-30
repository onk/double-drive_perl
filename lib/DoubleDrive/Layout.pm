use v5.42;
use experimental 'class';

class DoubleDrive::Layout {
    use Tickit::Widget::FloatBox;
    use Tickit::Widget::HBox;
    use Tickit::Widget::VBox;
    use Tickit::Widget::Static;
    use DoubleDrive::Pane;

    sub build ($class, %args) {
        my $status_bar = Tickit::Widget::Static->new(
            text => "",
            align => "left",
        );
        my $on_status_change = sub ($text) { $status_bar->set_text($text) };

        my $left_pane  = DoubleDrive::Pane->new(path => $args{left_path},  on_status_change => $on_status_change, is_active => true);
        my $right_pane = DoubleDrive::Pane->new(path => $args{right_path}, on_status_change => $on_status_change);

        my $float_box = Tickit::Widget::FloatBox->new;

        my $vbox = Tickit::Widget::VBox->new;
        my $hbox = Tickit::Widget::HBox->new(spacing => 1);

        $hbox->add($left_pane->widget,  expand => 1);
        $hbox->add($right_pane->widget, expand => 1);

        $vbox->add($hbox,      expand => 1);
        $vbox->add($status_bar);

        $float_box->set_base_child($vbox);

        return {
            float_box => $float_box,
            status_bar => $status_bar,
            left_pane => $left_pane,
            right_pane => $right_pane,
        };
    }
}
