use v5.42;
use utf8;

use Test2::V0;

use lib 'lib';
use DoubleDrive::CommandLineMode;

{
    package MockTickit;
    sub new ($class) {
        bless { handlers => {}, next_id => 0 }, $class;
    }
    sub rootwin ($self) { $self }
    sub bind_event ($self, %args) {
        my $id = $self->{next_id}++;
        $self->{handlers}{$id} = { event => $args{key}, cb => $args{key} };
        return $id;
    }
    sub unbind_event_id ($self, $id) {
        delete $self->{handlers}{$id} if defined $id;
    }
    sub get_handler ($self, $id) {
        return $self->{handlers}{$id};
    }
    sub handler_count ($self) {
        return scalar(keys %{ $self->{handlers} });
    }
}

{
    package MockKeyDispatcher;
    sub new ($class) {
        bless { in_cmdline => 0 }, $class;
    }
    sub enter_command_line_mode ($self) { $self->{in_cmdline} = 1 }
    sub exit_command_line_mode ($self) { $self->{in_cmdline} = 0 }
    sub is_in_command_line_mode ($self) { $self->{in_cmdline} }
}

{
    package MockKeyInfo;
    sub new ($class, $type, $str) {
        bless { type => $type, str => $str }, $class;
    }
    sub type ($self) { $self->{type} }
    sub str ($self) { $self->{str} }
}

subtest 'mode state transitions' => sub {
    my $tickit = MockTickit->new;
    my $key_dispatcher = MockKeyDispatcher->new;
    my $mode = DoubleDrive::CommandLineMode->new(
        tickit => $tickit,
        key_dispatcher => $key_dispatcher,
    );

    ok !$key_dispatcher->is_in_command_line_mode(), 'not in command line mode initially';

    $mode->enter({});
    ok $key_dispatcher->is_in_command_line_mode(), 'in command line mode after enter';
    is $tickit->handler_count(), 1, 'one event handler registered';

    $mode->exit();
    ok !$key_dispatcher->is_in_command_line_mode(), 'not in command line mode after exit';
    is $tickit->handler_count(), 0, 'event handler cleaned up';
};

subtest 'cleanup is idempotent' => sub {
    my $tickit = MockTickit->new;
    my $key_dispatcher = MockKeyDispatcher->new;
    my $mode = DoubleDrive::CommandLineMode->new(
        tickit => $tickit,
        key_dispatcher => $key_dispatcher,
    );

    $mode->enter({});
    is $tickit->handler_count(), 1, 'handler registered';

    $mode->exit();
    is $tickit->handler_count(), 0, 'handler cleaned up';

    ok lives { $mode->exit() }, 'second exit does not die';
    is $tickit->handler_count(), 0, 'still zero handlers';
};

subtest 'on_init callback' => sub {
    my $tickit = MockTickit->new;
    my $key_dispatcher = MockKeyDispatcher->new;
    my $mode = DoubleDrive::CommandLineMode->new(
        tickit => $tickit,
        key_dispatcher => $key_dispatcher,
    );

    my $init_called = 0;
    $mode->enter({
        on_init => sub { $init_called++ }
    });

    is $init_called, 1, 'on_init called once on enter';
};

subtest 'on_change callback on text input' => sub {
    my $tickit = MockTickit->new;
    my $key_dispatcher = MockKeyDispatcher->new;
    my $mode = DoubleDrive::CommandLineMode->new(
        tickit => $tickit,
        key_dispatcher => $key_dispatcher,
    );

    my $changes = [];
    $mode->enter({
        on_change => sub ($buffer) { push @$changes, $buffer }
    });

    my $handler = $tickit->get_handler(0)->{cb};

    # Simulate text input
    my $info = MockKeyInfo->new("text", "a");
    $handler->(undef, undef, $info, undef);
    is $changes, ["a"], 'on_change called with "a"';

    $info = MockKeyInfo->new("text", "b");
    $handler->(undef, undef, $info, undef);
    is $changes, ["a", "ab"], 'on_change called with "ab"';
};

subtest 'on_change callback on backspace' => sub {
    my $tickit = MockTickit->new;
    my $key_dispatcher = MockKeyDispatcher->new;
    my $mode = DoubleDrive::CommandLineMode->new(
        tickit => $tickit,
        key_dispatcher => $key_dispatcher,
    );

    my $changes = [];
    $mode->enter({
        on_change => sub ($buffer) { push @$changes, $buffer }
    });

    my $handler = $tickit->get_handler(0)->{cb};

    # Add some text
    $handler->(undef, undef, MockKeyInfo->new("text", "a"), undef);
    $handler->(undef, undef, MockKeyInfo->new("text", "b"), undef);

    # Backspace
    $handler->(undef, undef, MockKeyInfo->new("key", "Backspace"), undef);
    is $changes->[-1], "a", 'on_change called after backspace with "a"';
};

subtest 'on_execute callback on Enter' => sub {
    my $tickit = MockTickit->new;
    my $key_dispatcher = MockKeyDispatcher->new;
    my $mode = DoubleDrive::CommandLineMode->new(
        tickit => $tickit,
        key_dispatcher => $key_dispatcher,
    );

    my $executed_buffer;
    $mode->enter({
        on_execute => sub ($buffer) { $executed_buffer = $buffer }
    });

    my $handler = $tickit->get_handler(0)->{cb};

    # Add text and press Enter
    $handler->(undef, undef, MockKeyInfo->new("text", "t"), undef);
    $handler->(undef, undef, MockKeyInfo->new("text", "e"), undef);
    $handler->(undef, undef, MockKeyInfo->new("text", "s"), undef);
    $handler->(undef, undef, MockKeyInfo->new("text", "t"), undef);
    $handler->(undef, undef, MockKeyInfo->new("key", "Enter"), undef);

    is $executed_buffer, "test", 'on_execute called with buffer content';
    ok !$key_dispatcher->is_in_command_line_mode(), 'mode exited after Enter';
};

subtest 'on_cancel callback on Escape' => sub {
    my $tickit = MockTickit->new;
    my $key_dispatcher = MockKeyDispatcher->new;
    my $mode = DoubleDrive::CommandLineMode->new(
        tickit => $tickit,
        key_dispatcher => $key_dispatcher,
    );

    my $cancel_called = 0;
    $mode->enter({
        on_cancel => sub { $cancel_called++ }
    });

    my $handler = $tickit->get_handler(0)->{cb};

    # Press Escape
    $handler->(undef, undef, MockKeyInfo->new("key", "Escape"), undef);

    is $cancel_called, 1, 'on_cancel called on Escape';
    ok !$key_dispatcher->is_in_command_line_mode(), 'mode exited after Escape';
};

subtest 'guard condition: events ignored when not in command line mode' => sub {
    my $tickit = MockTickit->new;
    my $key_dispatcher = MockKeyDispatcher->new;
    my $mode = DoubleDrive::CommandLineMode->new(
        tickit => $tickit,
        key_dispatcher => $key_dispatcher,
    );

    my $change_called = 0;
    $mode->enter({
        on_change => sub { $change_called++ }
    });

    my $handler = $tickit->get_handler(0)->{cb};

    # Exit mode but simulate delayed event
    $mode->exit();

    my $result = $handler->(undef, undef, MockKeyInfo->new("text", "x"), undef);
    is $result, 0, 'handler returns 0 when not in command line mode';
    is $change_called, 0, 'callback not called when not in mode';
};

subtest 'multibyte characters (Japanese)' => sub {
    my $tickit = MockTickit->new;
    my $key_dispatcher = MockKeyDispatcher->new;
    my $mode = DoubleDrive::CommandLineMode->new(
        tickit => $tickit,
        key_dispatcher => $key_dispatcher,
    );

    my $changes = [];
    $mode->enter({
        on_change => sub ($buffer) { push @$changes, $buffer }
    });

    my $handler = $tickit->get_handler(0)->{cb};

    # Simulate Japanese input
    $handler->(undef, undef, MockKeyInfo->new("text", "あ"), undef);
    is $changes->[0], "あ", 'Japanese character captured';

    $handler->(undef, undef, MockKeyInfo->new("text", "い"), undef);
    is $changes->[1], "あい", 'Multiple Japanese characters captured';
};

subtest 'prevent duplicate handler registration' => sub {
    my $tickit = MockTickit->new;
    my $key_dispatcher = MockKeyDispatcher->new;
    my $mode = DoubleDrive::CommandLineMode->new(
        tickit => $tickit,
        key_dispatcher => $key_dispatcher,
    );

    $mode->enter({});
    is $tickit->handler_count(), 1, 'first enter registers handler';

    $mode->enter({});
    is $tickit->handler_count(), 1, 'second enter cleans up old handler first';
};

subtest 'buffer cleared on enter' => sub {
    my $tickit = MockTickit->new;
    my $key_dispatcher = MockKeyDispatcher->new;
    my $mode = DoubleDrive::CommandLineMode->new(
        tickit => $tickit,
        key_dispatcher => $key_dispatcher,
    );

    my $final_buffer;
    $mode->enter({
        on_execute => sub ($buffer) { $final_buffer = $buffer }
    });

    my $handler1 = $tickit->get_handler(0)->{cb};
    $handler1->(undef, undef, MockKeyInfo->new("text", "a"), undef);
    $handler1->(undef, undef, MockKeyInfo->new("key", "Enter"), undef);
    is $final_buffer, "a", 'first session has buffer';

    $mode->exit();

    # Enter again - buffer should be cleared
    $mode->enter({
        on_execute => sub ($buffer) { $final_buffer = $buffer }
    });

    my $handler2 = $tickit->get_handler(1)->{cb};
    $handler2->(undef, undef, MockKeyInfo->new("key", "Enter"), undef);
    is $final_buffer, "", 'second session starts with empty buffer';
};

done_testing;
