use v5.42;

package DoubleDrive::Test::Mock;

use Exporter 'import';
use Test2::Tools::Mock qw(mock);

our @EXPORT_OK = qw(mock_file_stat capture_widget_text StubStat mock_path mock_pane FIXED_MTIME);

# Fixed timestamp: 2025-01-15 10:30:00 UTC
use constant FIXED_MTIME => 1736937000;

{
    package DoubleDrive::Test::Mock::StubStat;
    sub new {
        my ($class, %args) = @_;
        return bless \%args, $class;
    }
    sub size  { shift->{size} }
    sub mtime { shift->{mtime} }
}

sub StubStat (%args) {
    return DoubleDrive::Test::Mock::StubStat->new(%args);
}

sub capture_widget_text ($window) {
    my @texts;
    my $mock = mock 'DoubleDrive::FileListView' => (
        override => [
            window => sub { $window },
        ],
        around => [
            set_rows => sub ($orig, $self, @args) {
                $self->$orig(@args);
                my $lines = $self->{lines} // [];
                my $text  = join("\n", map { $_->{text} } @$lines);
                push @texts, $text;
                return $self;
            },
        ],
    );
    return (\@texts, $mock);
}

sub mock_file_stat (%options) {
    my $size  = $options{size}  // 0;
    my $mtime = $options{mtime} // FIXED_MTIME;

    return mock 'Path::Tiny' => (
        override => [
            stat => sub { StubStat(size => $size, mtime => $mtime) },
        ],
    );
}

# Mock Path::Tiny object for Command tests
{
    package DoubleDrive::Test::Mock::MockPath;
    sub new($class, $name) {
        bless { name => $name }, $class;
    }
    sub basename($self) { $self->{name} }
    sub stringify($self) { $self->{name} }
}

sub mock_path ($name) {
    return DoubleDrive::Test::Mock::MockPath->new($name);
}

# Mock Pane for Command tests
{
    package DoubleDrive::Test::Mock::MockPane;
    sub new($class, %args) {
        bless {
            files => $args{files} // [],
            current_path => $args{current_path} // DoubleDrive::Test::Mock::MockPath->new('/tmp'),
            reload_called => 0,
        }, $class;
    }
    sub get_files_to_operate($self) { $self->{files} }
    sub reload_directory($self) { $self->{reload_called}++ }
    sub reload_called($self) { $self->{reload_called} }
    sub current_path($self) { $self->{current_path} }
}

sub mock_pane (%args) {
    return DoubleDrive::Test::Mock::MockPane->new(%args);
}
