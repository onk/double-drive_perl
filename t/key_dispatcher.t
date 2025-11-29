use v5.42;

use Test2::V0;

use lib 'lib';
use DoubleDrive::KeyDispatcher;

{
    package MockTickit;
    sub new { bless { bound => {} }, shift }
    sub bind_key {
        my ($self, $key, $cb) = @_;
        $self->{bound}{$key} = $cb;
    }
    sub bound { $_[0]->{bound} }
}

subtest 'normal vs dialog bindings' => sub {
    my $tickit = MockTickit->new;
    my $dispatcher = DoubleDrive::KeyDispatcher->new(tickit => $tickit);

    my $normal = 0;
    my $dialog = 0;

    $dispatcher->bind_normal('a' => sub { $normal++ });
    is scalar(keys %{ $tickit->bound }), 1, 'normal bind registers key once';

    $tickit->bound->{a}->();
    is $normal, 1, 'normal callback fired';

    $dispatcher->bind_dialog('a' => sub { $dialog++ });
    is scalar(keys %{ $tickit->bound }), 1, 'dialog bind reuses existing binding';

    $dispatcher->enter_dialog_mode();
    $tickit->bound->{a}->();
    is [$normal, $dialog], [1, 1], 'dialog callback takes precedence';

    $dispatcher->exit_dialog_mode();
    $tickit->bound->{a}->();
    is [$normal, $dialog], [2, 1], 'back to normal callback after dialog exit';
};

subtest 'multiple keys and overwrite' => sub {
    my $tickit = MockTickit->new;
    my $dispatcher = DoubleDrive::KeyDispatcher->new(tickit => $tickit);

    my ($a1, $a2, $b) = (0, 0, 0);
    $dispatcher->bind_normal('a' => sub { $a1++ });
    $dispatcher->bind_normal('b' => sub { $b++ });

    is scalar(keys %{ $tickit->bound }), 2, 'two keys bound once';

    $tickit->bound->{a}->();
    $tickit->bound->{b}->();
    is [$a1, $a2, $b], [1, 0, 1], 'initial callbacks fire';

    # overwrite normal binding for a
    $dispatcher->bind_normal('a' => sub { $a2++ });
    $tickit->bound->{a}->();
    is [$a1, $a2, $b], [1, 1, 1], 'new binding replaces old for same key';
};

subtest 'dialog mode with missing dialog binding does nothing' => sub {
    my $tickit = MockTickit->new;
    my $dispatcher = DoubleDrive::KeyDispatcher->new(tickit => $tickit);

    my $normal = 0;
    $dispatcher->bind_normal('x' => sub { $normal++ });
    $dispatcher->enter_dialog_mode();  # no dialog binding for x

    ok(
        lives { $tickit->bound->{x}->() },
        'invoking bound key with no dialog handler does not die'
    );
    is $normal, 0, 'no callback fired in dialog mode when none registered';
};

done_testing;
