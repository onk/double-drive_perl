use v5.42;
use utf8;
use Test2::V0;
use Path::Tiny qw(path tempdir);

use lib 'lib';
use DoubleDrive::FileListItem;

subtest 'construction' => sub {
    my $path = path('/tmp/test.txt');
    my $item = DoubleDrive::FileListItem->new(path => $path);

    is $item->path, $path, 'path stored';
    is $item->is_selected, false, 'not selected by default';
    is $item->is_match, false, 'not match by default';
};

subtest 'toggle_selected' => sub {
    my $item = DoubleDrive::FileListItem->new(path => path('/tmp/test.txt'));

    is $item->is_selected, false, 'initially false';

    $item->toggle_selected();
    is $item->is_selected, true, 'toggled to true';

    $item->toggle_selected();
    is $item->is_selected, false, 'toggled back to false';
};

subtest 'set_match' => sub {
    my $item = DoubleDrive::FileListItem->new(path => path('/tmp/test.txt'));

    is $item->is_match, false, 'initially false';

    $item->set_match(true);
    is $item->is_match, true, 'set to true';

    $item->set_match(false);
    is $item->is_match, false, 'set to false';
};

subtest 'is_dir and stat' => sub {
    my $tempdir = tempdir;
    my $file = path($tempdir)->child('test.txt');
    $file->spew("test");

    my $file_item = DoubleDrive::FileListItem->new(path => $file);
    ok !$file_item->is_dir, 'file is not dir';
    ok defined($file_item->stat), 'stat returns value';

    my $dir_item = DoubleDrive::FileListItem->new(path => path($tempdir));
    ok $dir_item->is_dir, 'dir is dir';
};

subtest 'is_archive' => sub {
    my $tempdir = tempdir;

    subtest 'detects ZIP files' => sub {
        my $zip_file = $tempdir->child('archive.zip');
        $zip_file->touch;

        my $item = DoubleDrive::FileListItem->new(path => $zip_file);
        ok $item->is_archive, 'detects .zip file as archive';
    };

    subtest 'case insensitive detection' => sub {
        my $zip_file = $tempdir->child('ARCHIVE.ZIP');
        $zip_file->touch;

        my $item = DoubleDrive::FileListItem->new(path => $zip_file);
        ok $item->is_archive, 'detects .ZIP file as archive (uppercase)';
    };

    subtest 'non-archive files' => sub {
        my $txt_file = $tempdir->child('test.txt');
        $txt_file->touch;

        my $item = DoubleDrive::FileListItem->new(path => $txt_file);
        ok !$item->is_archive, 'regular file is not archive';
    };

    subtest 'directories are not archives' => sub {
        my $dir = $tempdir->child('dir_archive.zip');
        $dir->mkpath;

        my $item = DoubleDrive::FileListItem->new(path => $dir);
        ok !$item->is_archive, 'directory named .zip is not archive';
    };
};

subtest 'basename and stringify' => sub {
    my $tempdir = tempdir;
    my $file = $tempdir->child('test.txt');
    $file->touch;

    my @children = $tempdir->children;
    my $item = DoubleDrive::FileListItem->new(path => $children[0]);

    is $item->basename, 'test.txt', 'basename';
    ok utf8::is_utf8($item->basename), 'basename is internal string';
    ok utf8::is_utf8($item->stringify), 'stringify is internal string';
};

subtest 'NFC normalization' => sub {
    use Unicode::Normalize qw(NFD NFC);

    my $tempdir = tempdir;

    # Create filename in NFD form (as macOS does)
    my $nfd_filename = NFD('ポ') . '.txt';  # ポ in NFD = U+30DB + U+309A
    my $file = $tempdir->child($nfd_filename);
    $file->touch;

    # Get the file from children() to simulate real usage
    my @children = $tempdir->children;
    is scalar(@children), 1, 'one file created';

    my $item = DoubleDrive::FileListItem->new(path => $children[0]);
    my $base = $item->basename;

    ok utf8::is_utf8($base), 'internal string';

    # basename should be NFC normalized
    my $expected_nfc = NFC('ポ') . '.txt';  # ポ in NFC = U+30DD
    is $base, $expected_nfc, 'NFD -> NFC normalized';
    isnt $base, $nfd_filename, 'not the same as NFD input';
};

done_testing;
