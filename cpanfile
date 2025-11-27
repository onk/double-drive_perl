requires 'File::MimeInfo';
requires 'Path::Tiny';
requires 'Term::ReadKey';
requires 'Tickit';
requires 'Tickit::Widget::Frame';
requires 'Tickit::Widget::GridBox';
requires 'Tickit::Widget::HBox';
requires 'Tickit::Widget::Scroller';
requires 'Tickit::Widget::VBox';
requires 'Unicode::GCString';

on develop => sub {
    requires 'Perl::Critic';
    requires 'Perl::Tidy';
};
