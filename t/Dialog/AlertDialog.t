use v5.42;
use utf8;

use Test2::V0;

use lib 'lib';
use DoubleDrive::Dialog::AlertDialog;

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

subtest 'instruction text' => sub {
    my $dialog = DoubleDrive::Dialog::AlertDialog->new(
        tickit => MockTickit->new,
        float_box => MockFloatBox->new,
        key_scope => MockScope->new,
        title => 'Alert',
        message => 'message',
        on_ack => sub { },
    );

    is $dialog->_instruction_text, 'Press Enter or Escape to close', 'shows close instruction';
};

subtest 'key bindings registered on show' => sub {
    my $scope = MockScope->new;

    my $dialog = DoubleDrive::Dialog::AlertDialog->new(
        tickit => MockTickit->new,
        float_box => MockFloatBox->new,
        key_scope => $scope,
        title => 'Alert',
        message => 'message',
        on_ack => sub { },
    );

    $dialog->show();

    my $bindings = $scope->bindings;
    is $bindings, hash {
        field Enter => D();
        field Escape => D();
        end();
    }, 'all expected keys bound';
};

subtest 'Enter and Escape trigger on_ack' => sub {
    my $scope = MockScope->new;
    my $ack_count = 0;

    my $dialog = DoubleDrive::Dialog::AlertDialog->new(
        tickit => MockTickit->new,
        float_box => MockFloatBox->new,
        key_scope => $scope,
        title => 'Alert',
        message => 'message',
        on_ack => sub { $ack_count++ },
    );

    $dialog->show();

    my $bindings = $scope->bindings;

    $bindings->{Enter}->();
    is $ack_count, 1, 'Enter triggers on_ack';

    $bindings->{Escape}->();
    is $ack_count, 2, 'Escape triggers on_ack';
};

subtest 'float added and removed on show/close' => sub {
    my $scope = MockScope->new;
    my $float_box = MockFloatBox->new;

    my $dialog = DoubleDrive::Dialog::AlertDialog->new(
        tickit => MockTickit->new,
        float_box => $float_box,
        key_scope => $scope,
        title => 'Alert',
        message => 'message',
        on_ack => sub { },
    );

    is scalar(@{ $float_box->floats }), 0, 'no float before show';

    $dialog->show();
    is scalar(@{ $float_box->floats }), 1, 'float added on show';

    # Trigger Enter to close
    my $bindings = $scope->bindings;
    $bindings->{Enter}->();
    is scalar(@{ $float_box->floats }), 0, 'float removed on close';
};

done_testing;
