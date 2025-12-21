use v5.42;
use utf8;
use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Path::Tiny qw(path tempfile);

our $system_calls;

BEGIN {
    # stub out external system calls early so implementation's calls are captured
    *CORE::GLOBAL::system = sub { push @$system_calls, [@_]; return 0 };
}

use DoubleDrive::Command::ViewFile;
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
    sub bind { my ($self, $k, $cb) = @_; $self->{binds}{$k} = $cb }
    sub trigger { my ($self, $k) = @_; $self->{binds}{$k}->() if $self->{binds}{$k} }
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

subtest 'single image file with kitty terminal' => sub {
    local $ENV{KITTY_WINDOW_ID} = 1;
    local $system_calls = [];
    my $file = DoubleDrive::FileListItem->new(path => path('/tmp/test_image.jpg'));
    my $pane = PaneStub->new([ $file ]);
    my @status_msgs;
    my $ctx  = Ctx->new($pane, sub { push @status_msgs, $_[0] });
    my $tickit = Tickit->new();
    my $scope = Scope->new();

    my $cmd = DoubleDrive::Command::ViewFile->new(
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
    is $scope->{binds}{'j'}, D(), 'scope has j bind';
    is $scope->{binds}{'k'}, D(), 'scope has k bind';
    is $scope->{binds}{'Down'}, D(), 'scope has Down bind';
    is $scope->{binds}{'Up'}, D(), 'scope has Up bind';
    is $status_msgs[-1], '/tmp/test_image.jpg', 'status shows path only for single image';
};

subtest 'text file preview' => sub {
    local $ENV{KITTY_WINDOW_ID} = 1;
    local $system_calls = [];

    my $temp = tempfile();
    $temp->spew_utf8("Hello\nWorld");
    my $file = DoubleDrive::FileListItem->new(path => $temp);

    my $pane = PaneStub->new([ $file ]);
    my @status_msgs;
    my $ctx  = Ctx->new($pane, sub { push @status_msgs, $_[0] });
    my $tickit = Tickit->new();
    my $scope = Scope->new();

    my $cmd = DoubleDrive::Command::ViewFile->new(
        context => $ctx,
        tickit => $tickit,
        dialog_scope => $scope,
        is_left => 0,
    );

    $cmd->execute();

    my $called_cmd = join ' ', @{$system_calls->[-1]};
    is $called_cmd, "bat --paging=always --pager=less -R +Gg $temp", 'bat invoked for text file';
    is $pane->{stopped}, 1, 'stop_preview called (after bat finishes)';
};

subtest 'binary file ignored' => sub {
    local $ENV{KITTY_WINDOW_ID} = 1;
    local $system_calls = [];

    my $temp = tempfile(SUFFIX => '.gz');
    $temp->spew_raw("\x1f\x8b\x08\x00" . ("\x00" x 10)); # gzip header
    my $file = DoubleDrive::FileListItem->new(path => $temp);

    my $pane = PaneStub->new([ $file ]);
    my $ctx  = Ctx->new($pane, sub { });
    my $tickit = Tickit->new();
    my $scope = Scope->new();

    my $cmd = DoubleDrive::Command::ViewFile->new(
        context => $ctx,
        tickit => $tickit,
        dialog_scope => $scope,
        is_left => 0,
    );

    $cmd->execute();

    is $pane->{started}, 0, 'start_preview not called for binary';
    is scalar @$system_calls, 0, 'no system call for binary';
};

subtest 'pdf file preview' => sub {
    local $ENV{KITTY_WINDOW_ID} = 1;
    local $system_calls = [];

    my $pdf_path = '/tmp/test.pdf';
    my $file = DoubleDrive::FileListItem->new(path => path($pdf_path));

    my $pane = PaneStub->new([ $file ]);
    my $ctx  = Ctx->new($pane, sub { });
    my $tickit = Tickit->new();
    my $scope = Scope->new();

    my $cmd = DoubleDrive::Command::ViewFile->new(
        context => $ctx,
        tickit => $tickit,
        dialog_scope => $scope,
        is_left => 0,
    );

    $cmd->execute();

    my $called_cmd = join ' ', @{$system_calls->[-1]};
    is $called_cmd, q{pdftotext -layout \/tmp\/test\.pdf - 2>&1 | bat --paging=always --pager='less -R +Gg' --language=txt}, 'pdftotext piped to bat with correct arguments';
    is $pane->{stopped}, 1, 'stop_preview called (after viewing)';
};

subtest 'not kitty terminal' => sub {
    local $ENV{KITTY_WINDOW_ID} = undef;
    local $ENV{TERM} = 'xterm-256color';
    local $system_calls = [];
    my $file = DoubleDrive::FileListItem->new(path => path('/tmp/test_image.png'));
    my $pane = PaneStub->new([ $file ]);
    my @status_msgs;
    my $ctx  = Ctx->new($pane, sub { push @status_msgs, $_[0] });
    my $tickit = Tickit->new();
    my $scope = Scope->new();

    my $cmd = DoubleDrive::Command::ViewFile->new(
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

subtest 'multiple images navigation' => sub {
    local $ENV{KITTY_WINDOW_ID} = 1;
    local $system_calls = [];
    my @files = (
        DoubleDrive::FileListItem->new(path => path('/tmp/image1.jpg')),
        DoubleDrive::FileListItem->new(path => path('/tmp/image2.png')),
        DoubleDrive::FileListItem->new(path => path('/tmp/image3.gif')),
    );
    my $pane = PaneStub->new(\@files);
    my @status_msgs;
    my $ctx  = Ctx->new($pane, sub { push @status_msgs, $_[0] });
    my $tickit = Tickit->new();
    my $scope = Scope->new();

    my $cmd = DoubleDrive::Command::ViewFile->new(
        context => $ctx,
        tickit => $tickit,
        dialog_scope => $scope,
        is_left => 1,
    );

    $cmd->execute();

    is $pane->{started}, 1, 'start_preview called';
    my $called_cmd = join ' ', @{$system_calls->[-1]};
    is $called_cmd, 'kitty +kitten icat --place 37x22@1x1 /tmp/image1.jpg', 'first image shown';
    is $status_msgs[-1], '[1/3] /tmp/image1.jpg', 'status shows position for multiple images';

    # Test j key (next image)
    $system_calls = [];
    @status_msgs = ();
    $scope->trigger('j');
    $called_cmd = join ' ', @{$system_calls->[-1]};
    is $called_cmd, 'kitty +kitten icat --place 37x22@1x1 /tmp/image2.png', 'second image shown after j';
    is $status_msgs[-1], '[2/3] /tmp/image2.png', 'status updated to 2/3';

    # Test k key (previous image)
    $system_calls = [];
    @status_msgs = ();
    $scope->trigger('k');
    $called_cmd = join ' ', @{$system_calls->[-1]};
    is $called_cmd, 'kitty +kitten icat --place 37x22@1x1 /tmp/image1.jpg', 'back to first image after k';
    is $status_msgs[-1], '[1/3] /tmp/image1.jpg', 'status back to 1/3';

    # Test wrap around (j at last image)
    $scope->trigger('j');  # to 2
    $scope->trigger('j');  # to 3
    $system_calls = [];
    @status_msgs = ();
    $scope->trigger('j');  # should wrap to 1
    $called_cmd = join ' ', @{$system_calls->[-1]};
    is $called_cmd, 'kitty +kitten icat --place 37x22@1x1 /tmp/image1.jpg', 'wraps to first image';
    is $status_msgs[-1], '[1/3] /tmp/image1.jpg', 'status wraps to 1/3';

    # Test wrap around (k at first image)
    $system_calls = [];
    @status_msgs = ();
    $scope->trigger('k');  # should wrap to 3
    $called_cmd = join ' ', @{$system_calls->[-1]};
    is $called_cmd, 'kitty +kitten icat --place 37x22@1x1 /tmp/image3.gif', 'wraps to last image';
    is $status_msgs[-1], '[3/3] /tmp/image3.gif', 'status wraps to 3/3';
};

subtest 'multiple files with mixed types' => sub {
    local $ENV{KITTY_WINDOW_ID} = 1;
    local $system_calls = [];
    my @files = (
        DoubleDrive::FileListItem->new(path => path('/tmp/image1.jpg')),
        DoubleDrive::FileListItem->new(path => path('/tmp/doc.txt')),
        DoubleDrive::FileListItem->new(path => path('/tmp/readme.md')),
        DoubleDrive::FileListItem->new(path => path('/tmp/image2.png')),
    );
    my $pane = PaneStub->new(\@files);
    my @status_msgs;
    my $ctx  = Ctx->new($pane, sub { push @status_msgs, $_[0] });
    my $tickit = Tickit->new();
    my $scope = Scope->new();

    my $cmd = DoubleDrive::Command::ViewFile->new(
        context => $ctx,
        tickit => $tickit,
        dialog_scope => $scope,
        is_left => 1,
    );

    $cmd->execute();

    is $pane->{started}, 1, 'start_preview called';
    my $called_cmd = join ' ', @{$system_calls->[-1]};
    is $called_cmd, 'kitty +kitten icat --place 37x22@1x1 /tmp/image1.jpg', 'first image (not txt) shown';
    is $status_msgs[-1], '[1/2] /tmp/image1.jpg', 'status shows 2 images (filtered)';
};

subtest 'compute_place' => sub {

    # create minimal objects to instantiate
    my $pane = PaneStub->new([]);
    my $ctx = Ctx->new($pane, sub {});
    my $tickit = Tickit->new();
    my $scope = Scope->new();
    my $obj = DoubleDrive::Command::ViewFile->new(
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
