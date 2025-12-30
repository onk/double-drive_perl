use v5.42;
use utf8;

use Test2::V0;

use lib 'lib';
use DoubleDrive::Dialog::SortDialog;

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

subtest 'instruction text shows options with selection' => sub {
    my $dialog = DoubleDrive::Dialog::SortDialog->new(
        tickit => MockTickit->new,
        float_box => MockFloatBox->new,
        key_scope => MockScope->new,
        title => 'Sort',
        message => 'Select sort option',
        on_execute => sub { },
    );

    my $text = $dialog->_instruction_text();
    like $text, qr/^> \[N\]ame/, 'name option selected initially';
    like $text, qr/\[S\]ize/, 'size option shown';
    like $text, qr/\[T\]ime/, 'time option shown';
    like $text, qr/e\[X\]tension/, 'extension option shown';
};

subtest 'all keys are bound' => sub {
    my $scope = MockScope->new;

    my $dialog = DoubleDrive::Dialog::SortDialog->new(
        tickit => MockTickit->new,
        float_box => MockFloatBox->new,
        key_scope => $scope,
        title => 'Sort',
        message => 'Select',
        on_execute => sub { },
    );

    $dialog->show();

    my $bindings = $scope->bindings;
    is $bindings, hash {
        # Navigation
        field j => D();
        field k => D();
        field Down => D();
        field Up => D();
        field Enter => D();
        field Escape => D();

        # Direct selection (case insensitive)
        field n => D();
        field N => D();
        field s => D();
        field S => D();
        field t => D();
        field T => D();
        field x => D();
        field X => D();

        end();
    }, 'all expected keys bound';
};

subtest 'j/k navigation moves selection' => sub {
    my $scope = MockScope->new;

    my $dialog = DoubleDrive::Dialog::SortDialog->new(
        tickit => MockTickit->new,
        float_box => MockFloatBox->new,
        key_scope => $scope,
        title => 'Sort',
        message => 'Select',
        on_execute => sub { },
    );

    $dialog->show();

    my $bindings = $scope->bindings;

    # Initial - name selected
    like $dialog->_instruction_text(), qr/> \[N\]ame/, 'starts at name';

    # Move down
    $bindings->{j}->();
    like $dialog->_instruction_text(), qr/> \[S\]ize/, 'j moves to size';

    # Move down twice more
    $bindings->{j}->();
    $bindings->{j}->();
    like $dialog->_instruction_text(), qr/> e\[X\]tension/, 'j moves to extension';

    # Can't move past end
    $bindings->{j}->();
    like $dialog->_instruction_text(), qr/> e\[X\]tension/, 'j stops at end';

    # Move up
    $bindings->{k}->();
    like $dialog->_instruction_text(), qr/> \[T\]ime/, 'k moves to time';
};

subtest 'Enter executes selected option' => sub {
    my $scope = MockScope->new;
    my $float_box = MockFloatBox->new;
    my $executed_key;

    my $dialog = DoubleDrive::Dialog::SortDialog->new(
        tickit => MockTickit->new,
        float_box => $float_box,
        key_scope => $scope,
        title => 'Sort',
        message => 'Select',
        on_execute => sub { $executed_key = shift },
    );

    $dialog->show();
    is scalar(@{ $float_box->floats }), 1, 'float shown';

    my $bindings = $scope->bindings;

    # Move to 'size' and execute
    $bindings->{j}->();    # name -> size
    $bindings->{Enter}->();

    is $executed_key, 'size', 'executed with size sort_key';
    is scalar(@{ $float_box->floats }), 0, 'float removed after execute';
};

subtest 'direct key selects option immediately' => sub {
    my $scope = MockScope->new;
    my $float_box = MockFloatBox->new;
    my $executed_key;

    my $dialog = DoubleDrive::Dialog::SortDialog->new(
        tickit => MockTickit->new,
        float_box => $float_box,
        key_scope => $scope,
        title => 'Sort',
        message => 'Select',
        on_execute => sub { $executed_key = shift },
    );

    $dialog->show();

    my $bindings = $scope->bindings;

    # Press 't' directly for time
    $bindings->{t}->();

    is $executed_key, 'mtime', 'direct key t executes with mtime';
    is scalar(@{ $float_box->floats }), 0, 'float removed';
};

subtest 'direct keys are case insensitive' => sub {
    my $scope = MockScope->new;
    my $float_box = MockFloatBox->new;
    my $executed_key;

    my $dialog = DoubleDrive::Dialog::SortDialog->new(
        tickit => MockTickit->new,
        float_box => $float_box,
        key_scope => $scope,
        title => 'Sort',
        message => 'Select',
        on_execute => sub { $executed_key = shift },
    );

    $dialog->show();

    my $bindings = $scope->bindings;

    # Press 'X' (uppercase) for extension
    $bindings->{X}->();

    is $executed_key, 'ext', 'uppercase X executes with ext';
};

subtest 'Escape cancels' => sub {
    my $scope = MockScope->new;
    my $float_box = MockFloatBox->new;
    my $cancelled = 0;

    my $dialog = DoubleDrive::Dialog::SortDialog->new(
        tickit => MockTickit->new,
        float_box => $float_box,
        key_scope => $scope,
        title => 'Sort',
        message => 'Select',
        on_execute => sub { },
        on_cancel => sub { $cancelled++ },
    );

    $dialog->show();

    my $bindings = $scope->bindings;
    $bindings->{Escape}->();

    is $cancelled, 1, 'on_cancel called';
    is scalar(@{ $float_box->floats }), 0, 'float removed';
};

done_testing;
