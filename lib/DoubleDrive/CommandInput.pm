use v5.42;
use utf8;
use experimental 'class';

class DoubleDrive::CommandInput {
    field $buffer :reader = "";

    method add_char($char) {
        $buffer .= $char;
    }

    method delete_char() {
        return if length($buffer) == 0;
        $buffer = substr($buffer, 0, -1);
    }

    method clear() {
        $buffer = "";
    }
}
