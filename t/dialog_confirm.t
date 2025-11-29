use v5.42;

use Test2::V0;
use Tickit::Test qw(mk_term);

use lib 'lib';
use DoubleDrive::ConfirmDialog;
use DoubleDrive::KeyDispatcher;

{
    package MockTickit;
    sub new {
        my ($class, %args) = @_;
        return bless { term => $args{term}, bound => {} }, $class;
    }
    sub term { $_[0]->{term} }
    sub bind_key { my ($self, $key, $cb) = @_; $_[0]->{bound}{$key} = $cb }
    sub bound { $_[0]->{bound} }
}

{
    package MockFloatHandle;
    sub new { my ($class, $on_remove) = @_; bless { on_remove => $on_remove }, $class }
    sub remove { my ($self) = @_; $self->{on_remove}->() if $self->{on_remove} }
}

{
    package MockFloatBox;
    sub new { bless { floats => [] }, shift }
    sub add_float {
        my ($self, %args) = @_;
        my $record = \%args;
        push @{ $self->{floats} }, $record;
        return MockFloatHandle->new(sub {
            @{ $self->{floats} } = grep { $_ ne $record } @{ $self->{floats} };
        });
    }
    sub floats { $_[0]->{floats} }
}

sub dialog_env {
    my (%opts) = @_;
    my $term = mk_term(
        lines => $opts{rows} // 24,
        cols  => $opts{cols} // 80,
    );
    my $tickit = MockTickit->new(term => $term);
    my $float_box = MockFloatBox->new;
    my $dispatcher = DoubleDrive::KeyDispatcher->new(tickit => $tickit);

    my %dialog_args = (
        tickit => $tickit,
        float_box => $float_box,
        key_dispatcher => $dispatcher,
        title => $opts{title} // 'Confirm',
        message => $opts{message} // 'message',
        on_confirm => $opts{on_confirm} // sub {},
    );
    $dialog_args{on_cancel} = $opts{on_cancel} if exists $opts{on_cancel};

    my $dialog = DoubleDrive::ConfirmDialog->new(%dialog_args);

    return ($dialog, $tickit, $float_box, $dispatcher);
}

subtest 'instruction text toggles with selection' => sub {
    my ($dialog) = dialog_env();

    is $dialog->_instruction_text, "> [Y]es   [N]o", 'initially highlights yes';
    $dialog->toggle_option();
    is $dialog->_instruction_text, "  [Y]es > [N]o", 'toggle moves highlight to no';
    $dialog->toggle_option();
    is $dialog->_instruction_text, "> [Y]es   [N]o", 'toggle back to yes';
};

subtest 'bindings fire confirm path and close float' => sub {
    my ($confirm, $cancel) = (0, 0);
    my ($dialog, $tickit, $float_box) = dialog_env(
        on_confirm => sub { $confirm++ },
        on_cancel  => sub { $cancel++ },
    );

    $dialog->show();

    for my $key (qw(y Y n N Tab Enter Escape)) {
        ok exists $tickit->bound->{$key}, "$key key bound";
    }
    is scalar(@{ $float_box->floats }), 1, 'float added on show';

    $tickit->bound->{Enter}->();  # selected yes by default

    is [$confirm, $cancel], [1, 0], 'Enter triggers confirm callback';
    is scalar(@{ $float_box->floats }), 0, 'float removed after confirm';

    $tickit->bound->{Enter}->();
    is [$confirm, $cancel], [1, 0], 'callback not fired again after dialog close';
};

subtest 'cancel path via keys' => sub {
    my ($confirm, $cancel) = (0, 0);
    my ($dialog, $tickit, $float_box) = dialog_env(
        on_confirm => sub { $confirm++ },
        on_cancel  => sub { $cancel++ },
    );

    $dialog->show();

    $tickit->bound->{n}->();

    is [$confirm, $cancel], [0, 1], 'n triggers cancel callback';
    is scalar(@{ $float_box->floats }), 0, 'float removed on cancel';

    $tickit->bound->{Escape}->();
    is [$confirm, $cancel], [0, 1], 'dialog already closed so no extra callback';
};

subtest 'Tab toggles to no and Enter cancels' => sub {
    my ($confirm, $cancel) = (0, 0);
    my ($dialog, $tickit, $float_box) = dialog_env(
        on_confirm => sub { $confirm++ },
        on_cancel  => sub { $cancel++ },
    );

    $dialog->show();

    $tickit->bound->{Tab}->();   # switch to no
    is $dialog->_instruction_text, "  [Y]es > [N]o", 'selection moved to no';

    $tickit->bound->{Enter}->(); # should execute cancel path

    is [$confirm, $cancel], [0, 1], 'Enter executes cancel when no selected';
    is scalar(@{ $float_box->floats }), 0, 'float removed after cancel';
};

subtest 'on_cancel defaults to no-op when omitted' => sub {
    my ($dialog, $tickit, $float_box) = dialog_env(on_confirm => sub {});

    $dialog->show();

    ok exists $tickit->bound->{Escape}, 'Escape bound even without on_cancel';

    ok lives { $tickit->bound->{Escape}->() }, 'Escape does not die without on_cancel';
    is scalar(@{ $float_box->floats }), 0, 'float removed using default on_cancel';
};

done_testing;
