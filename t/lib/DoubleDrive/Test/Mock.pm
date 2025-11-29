use v5.42;

package DoubleDrive::Test::Mock;

use Exporter 'import';
use Test2::Tools::Mock qw(mock);

our @EXPORT_OK = qw(mock_file_stat capture_widget_text StubStat FIXED_MTIME);

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
    my $mock = mock 'DoubleDrive::TextWidget' => (
        override => [
            window   => sub { $window },
            set_lines => sub {
                my ($self, $lines) = @_;
                my $text = join("\n", map { $_->{text} } @$lines);
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
