use v5.42;
use utf8;

package DoubleDrive::Test::Time;

use Exporter 'import';
use Time::Piece ();

our @EXPORT_OK = qw(do_at sub_at);

our $TIME;

BEGIN {
    no warnings 'redefine';
    *CORE::GLOBAL::time = sub { defined $TIME ? $TIME : CORE::time() };
}

sub _to_epoch ($time) {
    my $tp = Time::Piece->strptime($time, '%Y-%m-%dT%H:%M:%SZ');
    return $tp->epoch;
}

sub do_at :prototype(&$) ($code, $time) {
    my $epoch = _to_epoch($time);
    local $TIME = $epoch;
    return $code->();
}

sub sub_at :prototype(&$) ($code, $time) {
    return sub { &do_at($code, $time) };
}
