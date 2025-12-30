use v5.42;
use utf8;

use Test2::V0;

use lib 'lib';
use DoubleDrive::Dialog::ConfirmDialog;

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
        push @{ $self->{floats} }, \%args;
        return bless { floats => $self->{floats}, record => \%args }, 'MockFloatHandle';
    }
    sub floats { $_[0]->{floats} }
}

{
    package MockFloatHandle;

    sub remove {
        my ($self) = @_;
        @{ $self->{floats} } = grep { $_ ne $self->{record} } @{ $self->{floats} };
    }
}

{
    package MockTickit;
    sub new { bless {}, shift }
    sub term { bless {}, 'MockTerm' }
}

{
    package MockTerm;
    sub get_size { return (24, 80) }
}

subtest 'instruction text toggles with selection' => sub {
    my $dialog = DoubleDrive::Dialog::ConfirmDialog->new(
        tickit => MockTickit->new,
        float_box => MockFloatBox->new,
        key_scope => MockScope->new,
        title => 'Confirm',
        message => 'message',
        on_execute => sub { },
    );

    is $dialog->_instruction_text, "> [Y]es   [N]o", 'initially highlights yes';
    $dialog->toggle_option();
    is $dialog->_instruction_text, "  [Y]es > [N]o", 'toggle moves to no';
    $dialog->toggle_option();
    is $dialog->_instruction_text, "> [Y]es   [N]o", 'toggle back to yes';
};

subtest 'key bindings registered on show' => sub {
    my $scope = MockScope->new;

    my $dialog = DoubleDrive::Dialog::ConfirmDialog->new(
        tickit => MockTickit->new,
        float_box => MockFloatBox->new,
        key_scope => $scope,
        title => 'Confirm',
        message => 'message',
        on_execute => sub { },
    );

    $dialog->show();

    my $bindings = $scope->bindings;
    is $bindings, hash {
        field y => D();
        field Y => D();
        field n => D();
        field N => D();
        field Tab => D();
        field Enter => D();
        field Escape => D();
        end();
    }, 'all expected keys bound';
};

subtest 'Direct keys trigger callbacks' => sub {
    my $scope = MockScope->new;
    my ($confirm_count, $cancel_count) = (0, 0);

    my $dialog = DoubleDrive::Dialog::ConfirmDialog->new(
        tickit => MockTickit->new,
        float_box => MockFloatBox->new,
        key_scope => $scope,
        title => 'Confirm',
        message => 'message',
        on_execute => sub { $confirm_count++ },
        on_cancel => sub { $cancel_count++ },
    );

    $dialog->show();

    my $bindings = $scope->bindings;

    $bindings->{y}->();
    is [ $confirm_count, $cancel_count ], [ 1, 0 ], 'y triggers confirm';

    $bindings->{n}->();
    is [ $confirm_count, $cancel_count ], [ 1, 1 ], 'n triggers cancel';

    $bindings->{Escape}->();
    is [ $confirm_count, $cancel_count ], [ 1, 2 ], 'Escape triggers cancel';
};

subtest 'Enter executes selected option' => sub {
    my $scope = MockScope->new;
    my ($confirm_count, $cancel_count) = (0, 0);

    my $dialog = DoubleDrive::Dialog::ConfirmDialog->new(
        tickit => MockTickit->new,
        float_box => MockFloatBox->new,
        key_scope => $scope,
        title => 'Confirm',
        message => 'message',
        on_execute => sub { $confirm_count++ },
        on_cancel => sub { $cancel_count++ },
    );

    $dialog->show();

    my $bindings = $scope->bindings;

    # Enter on yes (default)
    $bindings->{Enter}->();
    is [ $confirm_count, $cancel_count ], [ 1, 0 ], 'Enter executes confirm when yes selected';

    # Toggle to no, then Enter
    $bindings->{Tab}->();
    $bindings->{Enter}->();
    is [ $confirm_count, $cancel_count ], [ 1, 1 ], 'Enter executes cancel when no selected';

    # Toggle back to yes, then Enter
    $bindings->{Tab}->();
    $bindings->{Enter}->();
    is [ $confirm_count, $cancel_count ], [ 2, 1 ], 'Enter executes confirm after toggle back';
};

subtest 'on_cancel defaults to no-op when omitted' => sub {
    my $scope = MockScope->new;

    my $dialog = DoubleDrive::Dialog::ConfirmDialog->new(
        tickit => MockTickit->new,
        float_box => MockFloatBox->new,
        key_scope => $scope,
        title => 'Confirm',
        message => 'message',
        on_execute => sub { },
    );

    $dialog->show();

    my $bindings = $scope->bindings;
    ok exists $bindings->{Escape}, 'Escape bound even without on_cancel';

    ok lives { $bindings->{Escape}->() }, 'Escape does not die without on_cancel';
};

subtest 'float added and removed on show/close' => sub {
    my $scope = MockScope->new;
    my $float_box = MockFloatBox->new;

    my $dialog = DoubleDrive::Dialog::ConfirmDialog->new(
        tickit => MockTickit->new,
        float_box => $float_box,
        key_scope => $scope,
        title => 'Confirm',
        message => 'message',
        on_execute => sub { },
    );

    is scalar(@{ $float_box->floats }), 0, 'no float before show';

    $dialog->show();
    is scalar(@{ $float_box->floats }), 1, 'float added on show';

    # Trigger y to close
    my $bindings = $scope->bindings;
    $bindings->{y}->();
    is scalar(@{ $float_box->floats }), 0, 'float removed on close';
};

done_testing;
