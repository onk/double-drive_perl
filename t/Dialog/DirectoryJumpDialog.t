use v5.42;
use utf8;

use Test2::V0;

use lib 'lib';
use DoubleDrive::Dialog::DirectoryJumpDialog;

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
    sub new { bless {}, shift }
    sub term { bless {}, 'MockTerm' }
}

{
    package MockTerm;
    sub get_size { return (24, 80) }
}

subtest 'instruction text shows directories with selection' => sub {
    my $directories = [
        { key => '1', name => 'Home',     path => '/home/user' },
        { key => '2', name => 'Projects', path => '/home/user/projects' },
        { key => '3', name => 'Documents', path => '/home/user/docs' },
    ];

    my $dialog = DoubleDrive::Dialog::DirectoryJumpDialog->new(
        tickit => MockTickit->new,
        float_box => MockFloatBox->new,
        key_scope => MockScope->new,
        title => 'Jump to Directory',
        message => 'Select directory',
        directories => $directories,
        on_execute => sub {},
    );

    my $text = $dialog->_instruction_text();
    like $text, qr/^> \[1\] Home/, 'first directory selected initially';
    like $text, qr/\[2\] Projects/, 'second directory shown';
    like $text, qr/\[3\] Documents/, 'third directory shown';
};

subtest 'navigation keys are bound' => sub {
    my $scope = MockScope->new;
    my $directories = [
        { key => '1', name => 'Home', path => '/home/user' },
        { key => '2', name => 'Work', path => '/work' },
    ];

    my $dialog = DoubleDrive::Dialog::DirectoryJumpDialog->new(
        tickit => MockTickit->new,
        float_box => MockFloatBox->new,
        key_scope => $scope,
        title => 'Jump',
        message => 'Select',
        directories => $directories,
        on_execute => sub {},
    );

    $dialog->show();

    my $bindings = $scope->bindings;
    is $bindings, hash {
        field j => D();
        field k => D();
        field Down => D();
        field Up => D();
        field Enter => D();
        field Escape => D();
        field '1' => D();  # direct key
        field '2' => D();  # direct key
        end();
    }, 'all expected keys bound';
};

subtest 'j/k navigation moves selection' => sub {
    my $scope = MockScope->new;
    my $directories = [
        { key => '1', name => 'First',  path => '/first' },
        { key => '2', name => 'Second', path => '/second' },
        { key => '3', name => 'Third',  path => '/third' },
    ];

    my $dialog = DoubleDrive::Dialog::DirectoryJumpDialog->new(
        tickit => MockTickit->new,
        float_box => MockFloatBox->new,
        key_scope => $scope,
        title => 'Jump',
        message => 'Select',
        directories => $directories,
        on_execute => sub {},
    );

    $dialog->show();

    my $bindings = $scope->bindings;

    # Initial state - first item selected
    like $dialog->_instruction_text(), qr/> \[1\] First/, 'starts at first';

    # Move down
    $bindings->{j}->();
    like $dialog->_instruction_text(), qr/> \[2\] Second/, 'j moves to second';

    # Move down again
    $bindings->{j}->();
    like $dialog->_instruction_text(), qr/> \[3\] Third/, 'j moves to third';

    # Can't move past end
    $bindings->{j}->();
    like $dialog->_instruction_text(), qr/> \[3\] Third/, 'j stops at end';

    # Move up
    $bindings->{k}->();
    like $dialog->_instruction_text(), qr/> \[2\] Second/, 'k moves to second';
};

subtest 'Enter executes selected directory' => sub {
    my $scope = MockScope->new;
    my $float_box = MockFloatBox->new;
    my $executed_path;

    my $directories = [
        { key => '1', name => 'First',  path => '/first' },
        { key => '2', name => 'Second', path => '/second' },
    ];

    my $dialog = DoubleDrive::Dialog::DirectoryJumpDialog->new(
        tickit => MockTickit->new,
        float_box => $float_box,
        key_scope => $scope,
        title => 'Jump',
        message => 'Select',
        directories => $directories,
        on_execute => sub { $executed_path = shift },
    );

    $dialog->show();
    is scalar(@{$float_box->floats}), 1, 'float shown';

    my $bindings = $scope->bindings;

    # Move to second and execute
    $bindings->{j}->();
    $bindings->{Enter}->();

    is $executed_path, '/second', 'executed with second directory path';
    is scalar(@{$float_box->floats}), 0, 'float removed after execute';
};

subtest 'direct key selects and executes immediately' => sub {
    my $scope = MockScope->new;
    my $float_box = MockFloatBox->new;
    my $executed_path;

    my $directories = [
        { key => '1', name => 'First',  path => '/first' },
        { key => '2', name => 'Second', path => '/second' },
        { key => '3', name => 'Third',  path => '/third' },
    ];

    my $dialog = DoubleDrive::Dialog::DirectoryJumpDialog->new(
        tickit => MockTickit->new,
        float_box => $float_box,
        key_scope => $scope,
        title => 'Jump',
        message => 'Select',
        directories => $directories,
        on_execute => sub { $executed_path = shift },
    );

    $dialog->show();

    my $bindings = $scope->bindings;

    # Press '3' directly
    $bindings->{'3'}->();

    is $executed_path, '/third', 'direct key executes immediately';
    is scalar(@{$float_box->floats}), 0, 'float removed';
};

subtest 'Escape cancels' => sub {
    my $scope = MockScope->new;
    my $float_box = MockFloatBox->new;
    my $cancelled = 0;

    my $directories = [
        { key => '1', name => 'First', path => '/first' },
    ];

    my $dialog = DoubleDrive::Dialog::DirectoryJumpDialog->new(
        tickit => MockTickit->new,
        float_box => $float_box,
        key_scope => $scope,
        title => 'Jump',
        message => 'Select',
        directories => $directories,
        on_execute => sub {},
        on_cancel => sub { $cancelled++ },
    );

    $dialog->show();

    my $bindings = $scope->bindings;
    $bindings->{Escape}->();

    is $cancelled, 1, 'on_cancel called';
    is scalar(@{$float_box->floats}), 0, 'float removed';
};

done_testing;
