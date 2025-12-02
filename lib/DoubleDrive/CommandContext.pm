use v5.42;
use experimental 'class';

class DoubleDrive::CommandContext {
    field $active_pane :param :reader;
    field $opposite_pane :param :reader;
    field $on_status_change :param :reader;
    field $on_confirm :param :reader;
    field $on_alert :param :reader;
}
