use v5.42;
use utf8;
use Test2::V0;
use Test2::Tools::Mock qw(mock);
use POSIX qw(tzset);
use lib 't/lib';
use DoubleDrive::Test::Time qw(sub_at);
use Path::Tiny qw(path tempdir);
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use Archive::Tar;

use lib 'lib';
use DoubleDrive::ArchiveItem;
use DoubleDrive::FileListItem;

BEGIN {
    $ENV{TZ} = 'UTC';
    tzset();
}

# Helper function to create a test ZIP file
sub create_test_zip {
    my ($tempdir, $filename, $entries) = @_;

    my $zip = Archive::Zip->new();

    for my $entry (@$entries) {
        if ($entry->{type} eq 'file') {
            my $member = $zip->addString($entry->{content} // '', $entry->{path});
            $member->desiredCompressionMethod(COMPRESSION_DEFLATED);
            $member->setLastModFileDateTimeFromUnix($entry->{mtime}) if defined $entry->{mtime};
        } elsif ($entry->{type} eq 'dir') {
            my $member = $zip->addDirectory($entry->{path});
            $member->setLastModFileDateTimeFromUnix($entry->{mtime}) if defined $entry->{mtime};
        }
    }

    my $zip_path = $tempdir->child($filename);
    die "Failed to write ZIP" unless $zip->writeToFileNamed($zip_path->stringify) == AZ_OK;

    return $zip_path;
}

# Helper function to create a test tar.gz file
sub create_test_tar_gz {
    my ($tempdir, $filename, $entries) = @_;

    # Create a temporary directory structure for tar creation
    my $temp_root = $tempdir->child('.tar_build');
    $temp_root->mkpath;

    for my $entry (@$entries) {
        my $full_path = $temp_root->child($entry->{path});

        if ($entry->{type} eq 'file') {
            $full_path->parent->mkpath;
            $full_path->spew_raw($entry->{content} // '');
            if (defined $entry->{mtime}) {
                utime($entry->{mtime}, $entry->{mtime}, $full_path->stringify);
            }
        } elsif ($entry->{type} eq 'dir') {
            $full_path->mkpath;
            if (defined $entry->{mtime}) {
                utime($entry->{mtime}, $entry->{mtime}, $full_path->stringify);
            }
        }
    }

    # Create tar.gz from the temporary directory
    my $orig_cwd = Path::Tiny->cwd;
    chdir($temp_root->stringify) or die "Cannot chdir to $temp_root: $!";

    my $tar = Archive::Tar->new();

    for my $entry (@$entries) {
        my $path = $entry->{path};
        if (-e $path) {
            $tar->add_files($path);
        }
    }

    chdir($orig_cwd->stringify) or die "Cannot chdir back to $orig_cwd: $!";

    my $tar_gz_path = $tempdir->child($filename);
    die "Failed to write tar.gz" unless $tar->write($tar_gz_path->stringify, COMPRESS_GZIP);

    return $tar_gz_path;
}

subtest 'new_from_archive' => sub {
    subtest 'creates archive item from valid ZIP' => sub {
        my $tempdir = tempdir;
        my $zip_path = create_test_zip(
            $tempdir,
            'test.zip',
            [
                { type => 'file', path => 'file.txt', content => 'test' },
            ]
        );

        my $file_item = DoubleDrive::FileListItem->new(path => $zip_path);
        my $archive_item = DoubleDrive::ArchiveItem->new_from_archive($file_item);

        ok defined($archive_item), 'archive item created';
        ok $archive_item isa 'DoubleDrive::ArchiveItem', 'is ArchiveItem instance';
    };

    subtest 'dies on invalid archive' => sub {
        my $tempdir = tempdir;
        my $invalid_file = $tempdir->child('invalid.zip');
        $invalid_file->spew("not a zip file");

        my $file_item = DoubleDrive::FileListItem->new(path => $invalid_file);

        like dies { DoubleDrive::ArchiveItem->new_from_archive($file_item) },
            qr/Unsupported or corrupted archive/,
            'dies on invalid archive';
    };

    subtest 'dies on unsupported format' => sub {
        my $tempdir = tempdir;
        my $txt_file = $tempdir->child('test.txt');
        $txt_file->spew("not an archive");

        my $file_item = DoubleDrive::FileListItem->new(path => $txt_file);

        like dies { DoubleDrive::ArchiveItem->new_from_archive($file_item) },
            qr/Unsupported or corrupted archive/,
            'dies on unsupported format';
    };
};

subtest 'archive root' => sub {
    my $tempdir = tempdir;
    my $zip_path = create_test_zip(
        $tempdir,
        'test.zip',
        [
            { type => 'file', path => 'file.txt', content => 'test' },
        ]
    );

    my $file_item = DoubleDrive::FileListItem->new(path => $zip_path);
    my $archive_root = DoubleDrive::ArchiveItem->new_from_archive($file_item);

    is $archive_root->basename, 'test.zip', 'basename is archive filename';
    like $archive_root->stringify, qr/test\.zip::$/, 'stringify shows archive root';
    ok $archive_root->is_dir, 'archive root is directory';
    ok !$archive_root->is_archive, 'archive items are not archives (prevent nesting)';
    ok $archive_root->is_archive_root, 'is archive root';
    is $archive_root->stat, undef, 'archive root has no stat';
};

subtest 'children' => sub {
    subtest 'lists root entries' => sub {
        my $tempdir = tempdir;
        my $zip_path = create_test_zip(
            $tempdir,
            'test.zip',
            [
                { type => 'file', path => 'file1.txt', content => 'test1' },
                { type => 'file', path => 'file2.txt', content => 'test2' },
                { type => 'dir', path => 'subdir/' },
            ]
        );

        my $file_item = DoubleDrive::FileListItem->new(path => $zip_path);
        my $archive_root = DoubleDrive::ArchiveItem->new_from_archive($file_item);
        my $children = $archive_root->children();

        is scalar(@$children), 3, 'has three children';

        my $names = [ sort map { $_->basename } @$children ];
        is $names, [ 'file1.txt', 'file2.txt', 'subdir' ], 'correct file names';
    };

    subtest 'lists nested entries' => sub {
        my $tempdir = tempdir;
        my $zip_path = create_test_zip(
            $tempdir,
            'test.zip',
            [
                { type => 'file', path => 'dir/file.txt', content => 'nested' },
                { type => 'file', path => 'dir/subdir/deep.txt', content => 'deep' },
            ]
        );

        my $file_item = DoubleDrive::FileListItem->new(path => $zip_path);
        my $archive_root = DoubleDrive::ArchiveItem->new_from_archive($file_item);
        my $children = $archive_root->children();

        # Should only show "dir" as immediate child (implicit directory)
        is scalar(@$children), 1, 'has one implicit directory';
        is $children->[0]->basename, 'dir', 'implicit directory created';
        ok $children->[0]->is_dir, 'implicit entry is directory';
    };
};

subtest 'entry info' => sub {
    my $tempdir = tempdir;
    my $mtime = 1_609_459_200;    # 2021-01-01
    my $zip_path = create_test_zip(
        $tempdir,
        'test.zip',
        [
            { type => 'file', path => 'test.txt', content => 'hello world', mtime => $mtime },
            { type => 'dir', path => 'testdir/', mtime => $mtime },
        ]
    );

    my $file_item = DoubleDrive::FileListItem->new(path => $zip_path);
    my $archive_root = DoubleDrive::ArchiveItem->new_from_archive($file_item);
    my $children = $archive_root->children();

    my ($file_entry) = grep { $_->basename eq 'test.txt' } @$children;
    my ($dir_entry) = grep { $_->basename eq 'testdir' } @$children;

    subtest 'file entry' => sub {
        ok !$file_entry->is_dir, 'file is not directory';
        is $file_entry->basename, 'test.txt', 'basename';
        like $file_entry->stringify, qr/test\.zip::test\.txt$/, 'stringify includes path';

        my $stat = $file_entry->stat;
        ok defined($stat), 'stat returns value';
        is $stat->size, 11, 'correct file size (uncompressed)';
        is $stat->mtime, $mtime, 'correct mtime';

        is $file_entry->size, 11, 'size method works';
        is $file_entry->mtime, $mtime, 'mtime method works';
    };

    subtest 'directory entry' => sub {
        ok $dir_entry->is_dir, 'directory is directory';
        is $dir_entry->basename, 'testdir', 'basename (no trailing slash)';
        like $dir_entry->stringify, qr/test\.zip::testdir$/, 'stringify includes path';

        my $stat = $dir_entry->stat;
        ok defined($stat), 'stat returns value';
        is $stat->size, 0, 'directory size is 0';
    };
};

subtest 'parent navigation' => sub {
    subtest 'root parent goes to filesystem' => sub {
        my $tempdir = tempdir;
        my $zip_path = create_test_zip(
            $tempdir,
            'test.zip',
            [
                { type => 'file', path => 'file.txt', content => 'test' },
            ]
        );

        my $file_item = DoubleDrive::FileListItem->new(path => $zip_path);
        my $archive_root = DoubleDrive::ArchiveItem->new_from_archive($file_item);

        my $parent = $archive_root->parent();

        ok $parent isa 'DoubleDrive::FileListItem', 'parent is FileListItem';
        is $parent->stringify, $tempdir->stringify, 'parent is archive directory';
    };

    subtest 'entry parent is archive root' => sub {
        my $tempdir = tempdir;
        my $zip_path = create_test_zip(
            $tempdir,
            'test.zip',
            [
                { type => 'file', path => 'file.txt', content => 'test' },
            ]
        );

        my $file_item = DoubleDrive::FileListItem->new(path => $zip_path);
        my $archive_root = DoubleDrive::ArchiveItem->new_from_archive($file_item);
        my $children = $archive_root->children();
        my $file_entry = $children->[0];

        my $parent = $file_entry->parent();

        ok $parent isa 'DoubleDrive::ArchiveItem', 'parent is ArchiveItem';
        ok $parent->is_archive_root, 'parent is archive root';
    };

    subtest 'nested entry parent is intermediate directory' => sub {
        my $tempdir = tempdir;
        my $zip_path = create_test_zip(
            $tempdir,
            'test.zip',
            [
                { type => 'file', path => 'dir/subdir/file.txt', content => 'nested' },
            ]
        );

        my $file_item = DoubleDrive::FileListItem->new(path => $zip_path);
        my $archive_root = DoubleDrive::ArchiveItem->new_from_archive($file_item);

        # Navigate: root -> dir -> subdir -> file.txt
        my $dir = $archive_root->children()->[0];
        my $subdir = $dir->children()->[0];
        my $file = $subdir->children()->[0];

        is $file->basename, 'file.txt', 'reached file';

        my $parent = $file->parent();
        ok $parent isa 'DoubleDrive::ArchiveItem', 'parent is ArchiveItem';
        is $parent->basename, 'subdir', 'parent is subdir';

        my $grandparent = $parent->parent();
        is $grandparent->basename, 'dir', 'grandparent is dir';
    };
};

subtest 'UTF-8 handling' => sub {
    subtest 'Japanese filename (NFC normalization)' => sub {
        my $tempdir = tempdir;
        use Unicode::Normalize qw(NFD NFC);
        use Encode qw(encode_utf8);

        # Create ZIP with NFD filename (encoded as bytes for Archive::Zip)
        my $zip = Archive::Zip->new();
        my $nfd_filename = NFD('日本語') . '.txt';
        my $nfd_bytes = encode_utf8($nfd_filename);
        $zip->addString('content', $nfd_bytes);
        my $zip_path = $tempdir->child('test.zip');
        die "Failed to write ZIP" unless $zip->writeToFileNamed($zip_path->stringify) == AZ_OK;

        my $file_item = DoubleDrive::FileListItem->new(path => $zip_path);
        my $archive_root = DoubleDrive::ArchiveItem->new_from_archive($file_item);
        my $children = $archive_root->children();

        # basename should be NFC normalized
        my $expected_nfc = NFC('日本語') . '.txt';
        is $children->[0]->basename, $expected_nfc, 'NFD -> NFC normalized';
        ok utf8::is_utf8($children->[0]->basename), 'basename is internal string';
    };
};

subtest 'extname (inherited)' => sub {
    my $tempdir = tempdir;
    my $zip_path = create_test_zip(
        $tempdir,
        'test.zip',
        [
            { type => 'file', path => 'document.txt', content => 'test' },
            { type => 'file', path => 'archive.tar.gz', content => 'test' },
            { type => 'file', path => 'README', content => 'test' },
            { type => 'dir', path => 'testdir/' },
        ]
    );

    my $file_item = DoubleDrive::FileListItem->new(path => $zip_path);
    my $archive_root = DoubleDrive::ArchiveItem->new_from_archive($file_item);
    my $children = $archive_root->children();

    my %entries = map { $_->basename => $_ } @$children;

    is $entries{'document.txt'}->extname, '.txt', 'file with .txt extension';
    is $entries{'archive.tar.gz'}->extname, '.gz', 'file with .gz extension (last)';
    is $entries{'README'}->extname, '', 'file without extension';
    is $entries{'testdir'}->extname, '', 'directory has no extension';
};

subtest 'format methods (inherited)' => sub_at {
    my $tempdir = tempdir;
    my $mtime = 1_736_937_000;    # 2025-01-15 10:30:00
    my $zip_path = create_test_zip(
        $tempdir,
        'test.zip',
        [
            { type => 'file', path => 'test.txt', content => 'x' x 2048, mtime => $mtime },
        ]
    );

    my $file_item = DoubleDrive::FileListItem->new(path => $zip_path);
    my $archive_root = DoubleDrive::ArchiveItem->new_from_archive($file_item);
    my $children = $archive_root->children();
    my $file_entry = $children->[0];

    subtest 'format_size' => sub {
        is $file_entry->format_size, '   2.0K', 'formats size correctly';
    };

    subtest 'format_mtime' => sub {
        is $file_entry->format_mtime, '01/15 10:30', 'formats mtime correctly';
    };

    subtest 'format_name' => sub {
        is $file_entry->format_name(10), 'test.txt  ', 'pads short name';
        is $file_entry->format_name(5), 'te...', 'truncates long name';
    };
}
'2025-01-15T10:30:00Z';

subtest 'deep directory navigation' => sub {
    my $tempdir = tempdir;
    my $zip_path = create_test_zip(
        $tempdir,
        'test.zip',
        [
            { type => 'file', path => 'a/b/c/d/deep.txt', content => 'very deep' },
        ]
    );

    my $file_item = DoubleDrive::FileListItem->new(path => $zip_path);
    my $current = DoubleDrive::ArchiveItem->new_from_archive($file_item);

    # Navigate down: root -> a -> b -> c -> d -> deep.txt
    for my $expected_name (qw(a b c d deep.txt)) {
        my $children = $current->children();
        is scalar(@$children), 1, "has one child at level $expected_name";
        $current = $children->[0];
        is $current->basename, $expected_name, "navigated to $expected_name";
    }

    # Navigate up: deep.txt -> d -> c -> b -> a -> root
    for my $expected_name (qw(d c b a)) {
        my $parent = $current->parent();
        is $parent->basename, $expected_name, "navigated to parent $expected_name";
        $current = $parent;
    }

    # One more parent() to get from 'a' to archive root
    my $root = $current->parent();
    ok $root->is_archive_root, 'reached archive root';
};

subtest 'tar.gz integration' => sub {
    subtest 'basic integration' => sub {
        my $tempdir = tempdir;
        my $tar_gz_path = create_test_tar_gz(
            $tempdir,
            'test.tar.gz',
            [
                { type => 'file', path => 'file1.txt', content => 'test1' },
                { type => 'dir', path => 'subdir/' },
            ]
        );

        my $file_item = DoubleDrive::FileListItem->new(path => $tar_gz_path);
        my $archive_item = DoubleDrive::ArchiveItem->new_from_archive($file_item);

        ok defined($archive_item), 'archive item created from tar.gz';
        is $archive_item->basename, 'test.tar.gz', 'basename is tar.gz filename';
        ok $archive_item->is_archive_root, 'is archive root';

        my $children = $archive_item->children();
        is scalar(@$children), 2, 'has two children';

        my $names = [ sort map { $_->basename } @$children ];
        is $names, [ 'file1.txt', 'subdir' ], 'correct child names';
    };

    subtest 'navigation' => sub {
        my $tempdir = tempdir;
        my $tar_gz_path = create_test_tar_gz(
            $tempdir,
            'test.tar.gz',
            [
                { type => 'file', path => 'dir/nested.txt', content => 'nested file' },
            ]
        );

        my $file_item = DoubleDrive::FileListItem->new(path => $tar_gz_path);
        my $archive_root = DoubleDrive::ArchiveItem->new_from_archive($file_item);

        # Navigate down
        my $dir = $archive_root->children()->[0];
        is $dir->basename, 'dir', 'navigated to dir';
        ok $dir->is_dir, 'dir is directory';

        my $file = $dir->children()->[0];
        is $file->basename, 'nested.txt', 'navigated to nested.txt';
        ok !$file->is_dir, 'file is not directory';

        # Navigate up
        my $parent = $file->parent();
        is $parent->basename, 'dir', 'parent is dir';

        my $grandparent = $parent->parent();
        ok $grandparent->is_archive_root, 'grandparent is archive root';

        # Exit archive
        my $fs_parent = $grandparent->parent();
        ok $fs_parent isa 'DoubleDrive::FileListItem', 'exited to filesystem';
    };
};

done_testing;
