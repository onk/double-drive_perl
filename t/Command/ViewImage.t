use v5.42;
use utf8;
use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Path::Tiny qw(path);

my $system_calls;

BEGIN {
    # stub out external system calls early so implementation's calls are captured
    *CORE::GLOBAL::system = sub { push @$system_calls, [@_]; return 0 };
}

use DoubleDrive::Command::ViewImage;
use DoubleDrive::FileListItem;

use Tickit::Test qw(mk_term);
my $mock_tickit = mock 'Tickit' => (
    override => [
        new => sub {
            my ($class, %args) = @_;
            return bless { term => ::mk_term() }, $class;
        },
        term => sub { shift->{term} },
    ],
);

{
    package Scope;
    sub new { bless { binds => {} }, shift }
    sub bind { my ($self, $k, $cb) = @_; $self->{binds}{$k} = 1 }
}
{
    package PaneStub;
    sub new { my ($class, $files) = @_; return bless { started => 0, stopped => 0, files => $files || [] }, $class }
    sub get_files_to_operate { return $_[0]->{files} }
    sub start_preview { $_[0]->{started}++ }
    sub stop_preview  { $_[0]->{stopped}++ }
}
# Context stub
{
    package Ctx;
    sub new { my ($class, $pane, $on_status) = @_; return bless { pane => $pane, on => $on_status }, $class }
    sub active_pane { return $_[0]->{pane} }
    sub on_status_change { return $_[0]->{on} }
}

subtest 'image file with kitty terminal' => sub {
    local $ENV{KITTY_WINDOW_ID} = 1;
    $system_calls = [];
    my $file = DoubleDrive::FileListItem->new(path => path('/tmp/test_image.jpg'));
    my $pane = PaneStub->new([ $file ]);
    my @status_msgs;
    my $ctx  = Ctx->new($pane, sub { push @status_msgs, $_[0] });
    my $tickit = Tickit->new();
    my $scope = Scope->new();

    my $cmd = DoubleDrive::Command::ViewImage->new(
        context => $ctx,
        tickit => $tickit,
        dialog_scope => $scope,
        is_left => 1,
    );

    $cmd->execute();

    is $pane->{started}, 1, 'start_preview called for image';
    my $called_cmd = join ' ', @{$system_calls->[-1]};
    is $called_cmd, 'kitty +kitten icat --place 37x22@1x1 /tmp/test_image.jpg', 'kitty +kitten icat invoked';
    is $scope->{binds}{'v'}, D(), 'scope has v bind';
    is $scope->{binds}{'Enter'}, D(), 'scope has Enter bind';
    is $scope->{binds}{'Escape'}, D(), 'scope has Escape bind';
    is $status_msgs[-1], 'Viewing image - press v/Enter/Escape to close', 'status message set';
};

subtest 'non-image file' => sub {
    local $ENV{KITTY_WINDOW_ID} = 1;
    $system_calls = [];
    my $file = DoubleDrive::FileListItem->new(path => path('/tmp/not_image.txt'));
    my $pane = PaneStub->new([ $file ]);
    my @status_msgs;
    my $ctx  = Ctx->new($pane, sub { push @status_msgs, $_[0] });
    my $tickit = Tickit->new();
    my $scope = Scope->new();

    my $cmd = DoubleDrive::Command::ViewImage->new(
        context => $ctx,
        tickit => $tickit,
        dialog_scope => $scope,
        is_left => 0,
    );

    $cmd->execute();

    is $pane->{started}, 0, 'start_preview not called for non-image';
    is scalar @$system_calls, 0, 'no system call for non-image';
};

subtest 'not kitty terminal' => sub {
    local $ENV{KITTY_WINDOW_ID} = undef;
    local $ENV{TERM} = 'xterm-256color';
    $system_calls = [];
    my $file = DoubleDrive::FileListItem->new(path => path('/tmp/test_image.png'));
    my $pane = PaneStub->new([ $file ]);
    my @status_msgs;
    my $ctx  = Ctx->new($pane, sub { push @status_msgs, $_[0] });
    my $tickit = Tickit->new();
    my $scope = Scope->new();

    my $cmd = DoubleDrive::Command::ViewImage->new(
        context => $ctx,
        tickit => $tickit,
        dialog_scope => $scope,
        is_left => 1,
    );

    $cmd->execute();

    is $pane->{started}, 0, 'start_preview not called without kitty';
    is scalar @$system_calls, 0, 'no system call without kitty';
    is $status_msgs[-1], 'Image preview requires kitty terminal', 'error message shown';
};

subtest 'compute_place' => sub {

    # create minimal objects to instantiate
    my $pane = PaneStub->new([]);
    my $ctx = Ctx->new($pane, sub {});
    my $tickit = Tickit->new();
    my $scope = Scope->new();
    my $obj = DoubleDrive::Command::ViewImage->new(
        context => $ctx,
        tickit => $tickit,
        dialog_scope => $scope,
        is_left => 1,
    );

    is $obj->_compute_place(24,80,1), '37x21@1x1', 'compute_place for left pane';
    is $obj->_compute_place(24,80,0), '37x21@41x1', 'compute_place for right pane';
    is $obj->_compute_place(24,2,1), U(), 'compute_place returns undef when too narrow';
    is $obj->_compute_place(2,80,1), U(), 'compute_place returns undef when too short';

    # no done_testing here; single done_testing at EOF
};


done_testing();
