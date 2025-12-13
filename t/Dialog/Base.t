use v5.42;
use utf8;

use Test2::V0;

use lib 'lib';
use DoubleDrive::Dialog::AlertDialog;

# Tests for Base.pm _compute_layout() logic
#
# Layout field meanings:
#   wrap_width: Text wrapping width for message content
#   left:       Left margin (centers the dialog horizontally)
#   right:      Right margin (negative value = offset from right edge in Tickit float)
#   top:        Top margin
#
# Why right = -left:
#   Tickit::Widget::FloatBox requires symmetric margins as positive/negative pairs.
#   For example, left=22 and right=-22 on an 80-column terminal reserves
#   a centered region of width 36 (80 - 22 - 22).

{
    package MockScope;
    sub new { bless { bindings => {} }, shift }
    sub bind {
        my ($self, $key, $cb) = @_;
        $self->{bindings}{$key} = $cb;
    }
    sub bindings { $_[0]->{bindings} }
}

{
    package MockFloatBox;
    sub new { bless { floats => [] }, shift }
    sub add_float {
        my ($self, %args) = @_;
        push @{$self->{floats}}, \%args;
        return bless { floats => $self->{floats}, record => \%args }, 'MockFloatHandle';
    }
    sub floats { $_[0]->{floats} }
}

{
    package MockFloatHandle;
    sub remove {
        my ($self) = @_;
        @{$self->{floats}} = grep { $_ ne $self->{record} } @{$self->{floats}};
    }
}

{
    package MockTickit;
    sub new {
        my ($class, $rows, $cols) = @_;
        bless { rows => $rows, cols => $cols }, $class;
    }
    sub term {
        my ($self) = @_;
        bless { rows => $self->{rows}, cols => $self->{cols} }, 'MockTerm';
    }
}

{
    package MockTerm;
    sub get_size {
        my ($self) = @_;
        return ($self->{rows}, $self->{cols});
    }
}

subtest 'layout computation - standard terminal (80x24)' => sub {
    # Base.pm constants: MIN_WIDTH=30, IDEAL_MARGIN_SUM=44 (left 22 + right 22)
    # wrap_width = max(MIN_WIDTH, cols - IDEAL_MARGIN_SUM) = max(30, 36) = 36
    # left = (cols - wrap_width) / 2 = (80 - 36) / 2 = 22
    # top = rows / 4 = 24 / 4 = 6

    my $dialog = DoubleDrive::Dialog::AlertDialog->new(
        tickit => MockTickit->new(24, 80),
        float_box => MockFloatBox->new,
        key_scope => MockScope->new,
        title => 'Test',
        message => 'Short message',
        on_ack => sub {},
    );

    my $layout = $dialog->_compute_layout();

    is $layout->{text}, 'Short message';
    is $layout->{left}, 22;
    is $layout->{right}, -22;
    is $layout->{top}, 6;
};

subtest 'layout computation - small terminal (40x10)' => sub {
    # Base.pm constants: MIN_WIDTH=30, IDEAL_MARGIN_SUM=44 (left 22 + right 22)
    # wrap_width = max(MIN_WIDTH, cols - IDEAL_MARGIN_SUM) = max(30, -4) = 30
    # left = (cols - wrap_width) / 2 = (40 - 30) / 2 = 5
    # top = rows / 4 = 10 / 4 = 2

    my $dialog = DoubleDrive::Dialog::AlertDialog->new(
        tickit => MockTickit->new(10, 40),
        float_box => MockFloatBox->new,
        key_scope => MockScope->new,
        title => 'Test',
        message => 'Message',
        on_ack => sub {},
    );

    my $layout = $dialog->_compute_layout();

    is $layout->{left}, 5;
    is $layout->{right}, -5;
    is $layout->{top}, 2;
};

done_testing;
