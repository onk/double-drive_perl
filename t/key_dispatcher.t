use v5.42;
use utf8;

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

    my $scope = $dispatcher->dialog_scope;
    $scope->bind('a' => sub { $dialog++ });
    is scalar(keys %{ $tickit->bound }), 1, 'dialog bind reuses existing binding';

    $tickit->bound->{a}->();
    is [$normal, $dialog], [1, 1], 'dialog callback takes precedence';

    undef $scope;  # dialog scope destroyed -> exit dialog mode and clear dialog bindings
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
    my $scope = $dispatcher->dialog_scope;  # no dialog binding for x

    ok(
        lives { $tickit->bound->{x}->() },
        'invoking bound key with no dialog handler does not die'
    );
    is $normal, 0, 'no callback fired in dialog mode when none registered';

    undef $scope;
    $tickit->bound->{x}->();
    is $normal, 1, 'normal callback restored after scope destroyed';
};

subtest 'new scope after previous dialog still binds' => sub {
    my $tickit = MockTickit->new;
    my $dispatcher = DoubleDrive::KeyDispatcher->new(tickit => $tickit);

    my ($normal, $first, $second) = (0, 0, 0);

    $dispatcher->bind_normal('Enter' => sub { $normal++ });

    my $scope1 = $dispatcher->dialog_scope;
    $scope1->bind('Enter' => sub { $first++ });

    $tickit->bound->{Enter}->();
    is [$normal, $first, $second], [0, 1, 0], 'first scope takes precedence';

    undef $scope1;  # destroy first scope -> leave dialog mode
    $tickit->bound->{Enter}->();
    is [$normal, $first, $second], [1, 1, 0], 'normal binding restored after first scope';

    my $scope2 = $dispatcher->dialog_scope;
    $scope2->bind('Enter' => sub { $second++ });

    $tickit->bound->{Enter}->();
    is [$normal, $first, $second], [1, 1, 1], 'second scope binds correctly after prior scope';
};

subtest 'nested scopes restore outer bindings after inner closes' => sub {
    my $tickit = MockTickit->new;
    my $dispatcher = DoubleDrive::KeyDispatcher->new(tickit => $tickit);

    my ($normal, $outer, $inner) = (0, 0, 0);
    $dispatcher->bind_normal('Enter' => sub { $normal++ });

    my $outer_scope = $dispatcher->dialog_scope;
    $outer_scope->bind('Enter' => sub { $outer++ });

    my $inner_scope = $dispatcher->dialog_scope;
    $inner_scope->bind('Enter' => sub { $inner++ });

    $tickit->bound->{Enter}->();
    is [$normal, $outer, $inner], [0, 0, 1], 'inner scope binding active';

    undef $inner_scope;  # end inner scope, outer still active
    $tickit->bound->{Enter}->();
    is [$normal, $outer, $inner], [0, 1, 1], 'outer binding restored after inner scope ends';

    undef $outer_scope;
    $tickit->bound->{Enter}->();
    is [$normal, $outer, $inner], [1, 1, 1], 'normal binding restored after all scopes end';
};

done_testing;
