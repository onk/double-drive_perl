use v5.42;
use warnings;
use lib 'lib';

use Test2::V0;

use Future;
use Tickit;
use Tickit::Test qw(mk_term);
use DoubleDrive::Layout;
use DoubleDrive::KeyDispatcher;
use DoubleDrive::CommandLineMode;
use DoubleDrive::Dialog::ConfirmDialog;
use DoubleDrive::Dialog::AlertDialog;

# use DoubleDrive::App;
#
# We can't simply 'use DoubleDrive::App' because it would load Future::AsyncAwait.
# Instead, we provide a no-op await() stub and use load_app_module() to load App.pm
# with async/await syntax stripped out.
#
# Future::AsyncAwait uses PL_keyword_plugin to add 'async' and 'await' as keywords
# at the parser level. We can't override this with simple function definitions because:
# 1. 'async method' is parsed as two keywords, not a function call
# 2. PL_keyword_plugin requires XS code to modify
# 3. Even if we could override it, Future::AsyncAwait loads first from App.pm
#
# The load_app_module() function below uses regex to strip async/await syntax before
# eval, converting 'await $f' to 'main::await($f)'. This stub provides that function.
# In tests, we don't need real async behavior, so it just returns the Future as-is.
sub await($f) {
    return $f;
}

sub load_app_module {
    open my $fh, '<', 'lib/DoubleDrive/App.pm' or die "cannot read App.pm: $!";
    local $/;
    my $src = <$fh>;
    close $fh;

    $src =~ s/^\s*use Future::AsyncAwait.*\n//m;
    $src =~ s/\basync\s+method\s+/method /g;
    $src =~ s/\basync\s+sub\s+/sub /g;
    $src =~ s/\bawait\s+([^\n;]+)/main::await($1)/g;

    eval $src;
    die $@ if $@;
}

load_app_module();

# Test classes for App.t
#
# The actual implementation uses Perl 5.42's 'class' syntax with ADJUST blocks
# for initialization. Test2::Mock can override methods, but it cannot prevent
# ADJUST blocks from running during construction.
#
# These TestFoo classes exist to provide minimal test doubles that can be
# instantiated without triggering complex initialization logic (like Tickit
# widget setup). We use traditional 'package' syntax with simple 'sub new'
# constructors that we fully control.

{
    package TestPane;
    sub new($class, %args) { bless \%args, $class }
    sub set_active($self, $active) { }
    sub after_window_attached($self) { }
}

{
    package TestStatusBar;
    sub new($class, %args) { bless \%args, $class }
    sub set_text($self, $text) {
        push @{$self->{texts}}, $text if $self->{texts};
    }
}

{
    package TestDialog;
    sub new($class, %args) { bless \%args, $class }
    sub show($self) { }
    sub confirm($self) { $self->{on_execute}->() if $self->{on_execute} }
    sub cancel($self) { $self->{on_cancel}->() if $self->{on_cancel} }
    sub ack($self) { $self->{on_ack}->() if $self->{on_ack} }
}

{
    package TestDialogScope;
    sub new($class, %args) { bless \%args, $class }
}

# Helper to create basic app infrastructure mocks
# Returns: { mocks => {...}, components => { left_pane, right_pane, float_box, status_bar, ... } }
sub mock_basic_app {
    my %opts = @_;

    # Create test objects (can be overridden via opts)
    my $left_pane = $opts{left_pane} // TestPane->new;
    my $right_pane = $opts{right_pane} // TestPane->new;
    my $status_bar = $opts{status_bar} // TestStatusBar->new;
    my $tickit_obj;

    my $mocks = {};

    # Layout mock
    $mocks->{layout} = mock 'DoubleDrive::Layout' => (
        override => [
            build => sub {
                my ($class, %args) = @_;
                return {
                    left_pane => $left_pane,
                    right_pane => $right_pane,
                    float_box => undef,
                    status_bar => $status_bar,
                };
            },
        ],
    );

    # Tickit mock
    $mocks->{tickit} = mock 'Tickit' => (
        override => [
            new => sub {
                my ($class, %args) = @_;
                $tickit_obj = bless { root => $args{root}, term => mk_term }, $class;
                return $tickit_obj;
            },
            later => sub { my ($self, $cb) = @_; $cb->() },
            term => sub { shift->{term} },
        ],
    );

    # KeyDispatcher mock - extensible
    my @dispatcher_methods = (
        bind_normal => sub { },
    );
    if (my $extra = $opts{dispatcher_methods}) {
        push @dispatcher_methods, @$extra;
    }
    $mocks->{key_dispatcher} = mock 'DoubleDrive::KeyDispatcher' => (
        override => [@dispatcher_methods],
    );

    # CommandLineMode mock - no override needed, just let it construct normally
    $mocks->{cmdline} = mock 'DoubleDrive::CommandLineMode' => ();

    return {
        mocks => $mocks,
        components => {
            left_pane => $left_pane,
            right_pane => $right_pane,
            float_box => undef,
            status_bar => $status_bar,
            tickit => \$tickit_obj,  # reference since it's set during App->new
        },
    };
}

subtest 'initialization' => sub {
    my $mock_pane = mock 'TestPane' => (
        track => 1,
        override => [
            set_active => sub { },
            after_window_attached => sub { },
        ],
    );

    my $left_pane = TestPane->new;
    my $right_pane = TestPane->new;

    # Tickit::Term mock - track method calls including setctl_int
    my $mock_term = mock 'Tickit::Term' => (
        track => 1,
        override => [
            setctl_int => sub { },
        ],
    );

    my $setup = mock_basic_app(
        left_pane => $left_pane,
        right_pane => $right_pane,
    );

    my $app = DoubleDrive::App->new;

    is $app->active_pane, $left_pane, 'left pane is active initially';

    my $pane_tracking = $mock_pane->sub_tracking();
    is scalar @{$pane_tracking->{after_window_attached}}, 2, 'after_window_attached called twice (left and right panes)';

    my $term_tracking = $mock_term->sub_tracking();
    my $setctl_int_calls = $term_tracking->{setctl_int};
    is scalar @$setctl_int_calls, 1, 'setctl_int called once';
    is $setctl_int_calls->[0]{args}[1], 'mouse', 'first arg is mouse control';
    is $setctl_int_calls->[0]{args}[2], 0, 'mouse tracking disabled';
};

subtest 'pane switching' => sub {
    my $setup = mock_basic_app();
    my $c = $setup->{components};

    my $app = DoubleDrive::App->new;

    is $app->active_pane, $c->{left_pane}, 'left pane is active initially';

    $app->switch_pane();
    is $app->active_pane, $c->{right_pane}, 'switch_pane moves focus to right';
    is $app->opposite_pane, $c->{left_pane}, 'opposite_pane returns left when right is active';

    $app->switch_pane();
    is $app->active_pane, $c->{left_pane}, 'switch_pane toggles back to left';
    is $app->opposite_pane, $c->{right_pane}, 'opposite_pane returns right when left is active';
};

subtest 'key bindings' => sub {
    # NOTE: Key binding tests are covered by individual feature tests
    # (pane switching, search mode, etc.)
    # This subtest is reserved for future integration tests if needed.
    pass 'placeholder';
};

subtest 'search mode' => sub {
    # Note: This test doesn't use mock_basic_app because it needs highly customized mocks:
    # - KeyDispatcher: bind_normal captures key bindings for testing
    # - CommandLineMode: enter captures callbacks for simulating user input
    # - TestPane: needs custom methods (update_search, clear_search, _render)

    my $update_search_calls = [];
    my $clear_search_calls = 0;
    my $render_calls = 0;
    my $next_match_count = 0;

    my $left_pane = TestPane->new(
        update_search_calls => $update_search_calls,
        clear_search_calls => \$clear_search_calls,
        render_calls => \$render_calls,
        next_match_count => \$next_match_count,
    );
    my $right_pane = TestPane->new;

    my $status_texts = [];
    my $status_bar = TestStatusBar->new(texts => $status_texts);

    my $key_bindings = {};
    my $cmdline_enter_calls = [];
    my $last_cmdline_callbacks;

    my $mock_layout = mock 'DoubleDrive::Layout' => (
        override => [
            build => sub {
                my ($class, %args) = @_;
                return {
                    left_pane => $left_pane,
                    right_pane => $right_pane,
                    float_box => undef,
                    status_bar => $status_bar,
                };
            },
        ],
    );

    my $mock_tickit = mock 'Tickit' => (
        override => [
            new => sub {
                my ($class, %args) = @_;
                return bless { root => $args{root} }, $class;
            },
            later => sub { my ($self, $cb) = @_; $cb->() },
            term => sub { Tickit::Test::mk_term() },
        ],
    );

    my $mock_pane = mock 'TestPane' => (
        add => [
            update_search => sub {
                my ($self, $query) = @_;
                push @{$self->{update_search_calls}}, $query;
                return ${$self->{next_match_count}};
            },
            clear_search => sub {
                my ($self) = @_;
                ${$self->{clear_search_calls}}++;
            },
            _render => sub {
                my ($self) = @_;
                ${$self->{render_calls}}++;
            },
        ],
    );

    my $mock_key_dispatcher = mock 'DoubleDrive::KeyDispatcher' => (
        override => [
            bind_normal => sub {
                my ($self, $key, $cb) = @_;
                $key_bindings->{$key} = $cb;
            },
        ],
    );

    my $mock_cmdline = mock 'DoubleDrive::CommandLineMode' => (
        override => [
            enter => sub {
                my ($self, $callbacks) = @_;
                push @$cmdline_enter_calls, $callbacks;
                $last_cmdline_callbacks = $callbacks;
                $callbacks->{on_init}->() if $callbacks->{on_init};
            },
        ],
    );

    my $app = DoubleDrive::App->new;

    # Trigger the '/' key binding to enter search mode
    $key_bindings->{'/'}->();
    is scalar @$cmdline_enter_calls, 1, 'search command line entered';
    is $update_search_calls->[0], '', 'search init clears query';
    is $status_texts->[0], '/ (no matches)', 'status bar shows empty search state';

    # Simulate user typing 'abc' with 2 matches
    $next_match_count = 2;
    $last_cmdline_callbacks->{on_change}->('abc');
    is $status_texts->[-1], '/abc (2 matches)', 'status bar shows match count';
    is $update_search_calls->[-1], 'abc', 'pane receives query';

    # Simulate user typing 'zzz' with 0 matches
    $next_match_count = 0;
    $last_cmdline_callbacks->{on_change}->('zzz');
    is $status_texts->[-1], '/zzz (no matches)', 'status bar shows no match state';

    # Simulate execute (Enter key)
    $last_cmdline_callbacks->{on_execute}->('done');
    is $render_calls, 1, 'execute re-renders active pane';

    # Simulate cancel (Escape key)
    $last_cmdline_callbacks->{on_cancel}->();
    is $clear_search_calls, 1, 'cancel clears search';
    is $render_calls, 2, 'cancel renders active pane';
};

subtest 'confirm_dialog (confirmed)' => sub {
    my $dialog_scope_calls = 0;

    my $setup = mock_basic_app(
        dispatcher_methods => [
            dialog_scope => sub { $dialog_scope_calls++; TestDialogScope->new },
        ],
    );

    my $mock_confirm_dialog = mock 'DoubleDrive::Dialog::ConfirmDialog' => (
        track => 1,
        override => [
            new => sub ($class, %args) { TestDialog->new(%args) },
        ],
    );

    my $show_called = 0;
    my $mock_test_dialog = mock 'TestDialog' => (
        override => [
            show => sub ($self) {
                $show_called++;
                # Simulate user confirming immediately (pressing 'y' key)
                $self->confirm();
            },
        ],
    );

    my $app = DoubleDrive::App->new;

    my $future = $app->confirm_dialog('sure?', 'Title');
    is $dialog_scope_calls, 1, 'dialog scope entered for confirm';
    is $show_called, 1, 'dialog show() was called';
    my $result = $future->get;
    is $result, 1, 'confirm_dialog resolves when acknowledged';

    my $new_call = $mock_confirm_dialog->sub_tracking->{new}[0];
    my (undef, %args) = @{$new_call->{args}};
    is $args{message}, 'sure?', 'confirm dialog receives message';
    is $args{title}, 'Title', 'confirm dialog receives title';
};

subtest 'confirm_dialog (cancelled)' => sub {
    my $setup = mock_basic_app(
        dispatcher_methods => [
            dialog_scope => sub { TestDialogScope->new },
        ],
    );

    my $mock_confirm_dialog = mock 'DoubleDrive::Dialog::ConfirmDialog' => (
        track => 1,
        override => [
            new => sub ($class, %args) { TestDialog->new(%args) },
        ],
    );

    my $show_called = 0;
    my $mock_test_dialog = mock 'TestDialog' => (
        override => [
            show => sub ($self) {
                $show_called++;
                # Simulate user cancelling immediately (pressing 'n' or Escape key)
                $self->cancel();
            },
        ],
    );

    my $app = DoubleDrive::App->new;

    my $future = $app->confirm_dialog('nope');
    is $show_called, 1, 'dialog show() was called';
    eval { $future->get };
    like $@, qr/cancelled/, 'confirm_dialog rejects when cancelled';
};

subtest 'alert_dialog' => sub {
    my $setup = mock_basic_app(
        dispatcher_methods => [
            dialog_scope => sub { TestDialogScope->new },
        ],
    );

    my $mock_alert_dialog = mock 'DoubleDrive::Dialog::AlertDialog' => (
        track => 1,
        override => [
            new => sub ($class, %args) { TestDialog->new(%args) },
        ],
    );

    my $show_called = 0;
    my $mock_test_dialog = mock 'TestDialog' => (
        override => [
            show => sub ($self) {
                $show_called++;
                # Simulate user acknowledging immediately (pressing Enter or Escape key)
                $self->ack();
            },
        ],
    );

    my $app = DoubleDrive::App->new;

    my $future = $app->alert_dialog('boom', 'Error!');
    is $show_called, 1, 'dialog show() was called';
    $future->get;

    my $new_call = $mock_alert_dialog->sub_tracking->{new}[0];
    my (undef, %args) = @{$new_call->{args}};
    is $args{message}, 'boom', 'alert dialog receives message';
    is $args{title}, 'Error!', 'alert dialog receives title';
};

subtest 'command_context' => sub {
    my $status_texts = [];
    my $status_bar = TestStatusBar->new(texts => $status_texts);

    my $setup = mock_basic_app(status_bar => $status_bar);
    my $c = $setup->{components};

    my $app = DoubleDrive::App->new;
    my $ctx = $app->command_context();

    is $ctx->active_pane, $c->{left_pane}, 'context exposes active pane';
    is $ctx->opposite_pane, $c->{right_pane}, 'context exposes opposite pane';

    $ctx->on_status_change->('hello');
    is $status_texts->[0], 'hello', 'status change pushes to status bar';

    my $mock_app = mock 'DoubleDrive::App' => (
        track => 1,
        override => [
            confirm_dialog => sub ($self, @args) { Future->done('ok') },
            alert_dialog => sub ($self, @args) { Future->done('warn') },
        ],
    );

    is $ctx->on_confirm->('hey', 'Please')->get, 'ok', 'context confirm delegates to app confirm';
    my $tracking = $mock_app->sub_tracking();
    my $confirm_calls = $tracking->{confirm_dialog};
    ok $confirm_calls, 'confirm was called';
    is $confirm_calls->[0]{args}[0], $app, 'confirm closure passes app instance';
    is [$confirm_calls->[0]{args}[1], $confirm_calls->[0]{args}[2]], ['hey', 'Please'], 'confirm closure passes message and title';

    is $ctx->on_alert->('oops', 'Bad')->get, 'warn', 'context alert delegates to app alert';
    my $alert_calls = $tracking->{alert_dialog};
    ok $alert_calls, 'alert was called';
    is $alert_calls->[0]{args}[0], $app, 'alert closure passes app instance';
    is [$alert_calls->[0]{args}[1], $alert_calls->[0]{args}[2]], ['oops', 'Bad'], 'alert closure passes message and title';
};

done_testing;
