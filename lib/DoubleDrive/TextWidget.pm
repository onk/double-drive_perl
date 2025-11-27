use v5.42;

package DoubleDrive::TextWidget;
use parent 'Tickit::Widget::Static';

# Request minimal width - this allows HBox to distribute width evenly
sub cols { 1 }
