requires 'Archive::Tar';
requires 'Archive::Zip';
requires 'File::Copy::Recursive';
requires 'File::MimeInfo';
requires 'Future';
requires 'Future::AsyncAwait';
requires 'List::MoreUtils';
requires 'Path::Tiny';
requires 'Term::ReadKey';
requires 'Tickit';
requires 'Tickit::Widget::FloatBox';
requires 'Tickit::Widget::Frame';
requires 'Tickit::Widget::GridBox';
requires 'Tickit::Widget::HBox';
requires 'Tickit::Widget::Scroller';
requires 'Tickit::Widget::VBox';
requires 'Unicode::GCString';

on develop => sub {
    requires 'Perl::Critic';
    requires 'Perl::Tidy';
    requires 'Test2::Suite';
    requires 'Tickit::Test';
};
