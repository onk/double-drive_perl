use v5.42;
use utf8;

use Test2::V0;
use List::Util qw(max);
use Tickit::Test qw(mk_term);

use lib 'lib';
use DoubleDrive::AlertDialog;
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
    my $scope = $dispatcher->dialog_scope;

    my $dialog = DoubleDrive::AlertDialog->new(
        tickit => $tickit,
        float_box => $float_box,
        key_scope => $scope,
        title => $opts{title} // 'Alert',
        message => $opts{message} // 'message',
        on_ack => $opts{on_ack} // sub {},
    );

    return ($dialog, $tickit, $float_box);
}

subtest 'layout wraps message using terminal size' => sub {
    my ($dialog) = dialog_env(
        rows => 24,
        cols => 80,
        message => 'x' x 120,
    );

    my $layout = $dialog->_compute_layout();

    my @lines = split /\n/, $layout->{text};
    my $max_len = max(map { length $_ } @lines);

    ok $max_len <= 36 && $max_len >= 30, 'wrap width derived from cols';
    is $layout->{left}, 22, 'left margin centers dialog';
    is $layout->{top}, 6, 'top margin is quarter of rows';
    is $layout->{right}, -22, 'right margin mirrors left';
    is $dialog->_instruction_text, 'Press Enter or Escape to close', 'instruction text set';
};

subtest 'Enter confirms and closes once' => sub {
    my $ack = 0;
    my ($dialog, $tickit, $float_box) = dialog_env(on_ack => sub { $ack++ });

    $dialog->show();

    ok exists $tickit->bound->{Enter}, 'Enter key bound';
    ok exists $tickit->bound->{Escape}, 'Escape key bound';
    is scalar(@{ $float_box->floats }), 1, 'float added on show';

    $tickit->bound->{Enter}->();

    is $ack, 1, 'Enter triggers on_ack';
    is scalar(@{ $float_box->floats }), 0, 'float removed on close';

    $tickit->bound->{Enter}->();
    is $ack, 1, 'dialog mode exited so callback not called again';
};

subtest 'Escape cancels and callback runs' => sub {
    my $ack = 0;
    my ($dialog, $tickit, $float_box) = dialog_env(on_ack => sub { $ack++ });

    $dialog->show();

    $tickit->bound->{Escape}->();

    is $ack, 1, 'Escape triggers on_ack';
    is scalar(@{ $float_box->floats }), 0, 'float removed when cancelling';

    $tickit->bound->{Escape}->();
    is $ack, 1, 'bindings cleared after closing dialog';
};

done_testing;
