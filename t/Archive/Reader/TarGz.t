use v5.42;
use utf8;
use Test2::V0;
use POSIX qw(tzset);
use Path::Tiny qw(path tempdir);
use Archive::Tar;

use lib 'lib';
use DoubleDrive::Archive::Reader::TarGz;

BEGIN {
    $ENV{TZ} = 'UTC';
    tzset();
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
    # Change to temp_root directory and add files with relative paths
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

subtest 'TarGz reader construction' => sub {
    subtest 'reads valid tar.gz file' => sub {
        my $tempdir = tempdir;
        my $tar_gz_path = create_test_tar_gz(
            $tempdir,
            'test.tar.gz',
            [
                { type => 'file', path => 'file.txt', content => 'test' },
            ]
        );

        my $reader = DoubleDrive::Archive::Reader::TarGz->new(archive_path => $tar_gz_path);
        ok defined($reader), 'reader created';
        ok $reader isa 'DoubleDrive::Archive::Reader::TarGz', 'is TarGz reader';
    };

    subtest 'fails on invalid tar.gz' => sub {
        my $tempdir = tempdir;
        my $invalid_file = $tempdir->child('invalid.tar.gz');
        $invalid_file->spew("not a tar.gz file");

        like dies { DoubleDrive::Archive::Reader::TarGz->new(archive_path => $invalid_file) },
            qr/Failed to read tar\.gz archive/,
            'dies on invalid tar.gz';
    };
};

subtest 'list_entries - root level' => sub {
    my $tempdir = tempdir;
    my $tar_gz_path = create_test_tar_gz(
        $tempdir,
        'test.tar.gz',
        [
            { type => 'file', path => 'file1.txt', content => 'test1' },
            { type => 'file', path => 'file2.txt', content => 'test2' },
            { type => 'dir', path => 'subdir/' },
        ]
    );

    my $reader = DoubleDrive::Archive::Reader::TarGz->new(archive_path => $tar_gz_path);
    my $entries = $reader->list_entries('');

    is scalar(@$entries), 3, 'has three entries';

    my $names = [ sort map { $_->{basename} } @$entries ];
    is $names, [ 'file1.txt', 'file2.txt', 'subdir' ], 'correct file names';

    my ($file_entry) = grep { $_->{basename} eq 'file1.txt' } @$entries;
    ok !$file_entry->{is_dir}, 'file is not directory';
    is $file_entry->{size}, 5, 'correct file size';

    my ($dir_entry) = grep { $_->{basename} eq 'subdir' } @$entries;
    ok $dir_entry->{is_dir}, 'directory is directory';
    is $dir_entry->{size}, 0, 'directory size is 0';
};

subtest 'list_entries - implicit directories' => sub {
    my $tempdir = tempdir;
    my $tar_gz_path = create_test_tar_gz(
        $tempdir,
        'test.tar.gz',
        [
            { type => 'file', path => 'dir/file.txt', content => 'nested' },
            { type => 'file', path => 'dir/subdir/deep.txt', content => 'deep' },
        ]
    );

    my $reader = DoubleDrive::Archive::Reader::TarGz->new(archive_path => $tar_gz_path);
    my $entries = $reader->list_entries('');

    is scalar(@$entries), 1, 'has one implicit directory at root';
    is $entries->[0]{basename}, 'dir', 'implicit directory created';
    ok $entries->[0]{is_dir}, 'implicit entry is directory';

    my $dir_entries = $reader->list_entries('dir');
    my $names = [ sort map { $_->{basename} } @$dir_entries ];
    is $names, [ 'file.txt', 'subdir' ], 'dir contains file and subdir';
};

subtest 'list_entries - nested path' => sub {
    my $tempdir = tempdir;
    my $tar_gz_path = create_test_tar_gz(
        $tempdir,
        'test.tar.gz',
        [
            { type => 'file', path => 'a/b/c/deep.txt', content => 'very deep' },
        ]
    );

    my $reader = DoubleDrive::Archive::Reader::TarGz->new(archive_path => $tar_gz_path);

    my $entries_a = $reader->list_entries('a');
    is scalar(@$entries_a), 1, 'a/ has one child';
    is $entries_a->[0]{basename}, 'b', 'child is b';

    my $entries_ab = $reader->list_entries('a/b');
    is scalar(@$entries_ab), 1, 'a/b/ has one child';
    is $entries_ab->[0]{basename}, 'c', 'child is c';

    my $entries_abc = $reader->list_entries('a/b/c');
    is scalar(@$entries_abc), 1, 'a/b/c/ has one child';
    is $entries_abc->[0]{basename}, 'deep.txt', 'child is deep.txt';
};

subtest 'get_entry_info' => sub {
    my $tempdir = tempdir;
    my $mtime = 1_609_459_200;    # 2021-01-01
    my $tar_gz_path = create_test_tar_gz(
        $tempdir,
        'test.tar.gz',
        [
            { type => 'file', path => 'test.txt', content => 'hello world', mtime => $mtime },
            { type => 'dir', path => 'testdir/', mtime => $mtime },
        ]
    );

    my $reader = DoubleDrive::Archive::Reader::TarGz->new(archive_path => $tar_gz_path);

    subtest 'file entry info' => sub {
        my $info = $reader->get_entry_info('test.txt');
        ok defined($info), 'info returned';
        is $info->{basename}, 'test.txt', 'basename';
        ok !$info->{is_dir}, 'is not directory';
        is $info->{size}, 11, 'correct size';
        is $info->{mtime}, $mtime, 'correct mtime';
        ok defined($info->{mode}), 'mode is set';
    };

    subtest 'directory entry info' => sub {
        my $info = $reader->get_entry_info('testdir');
        ok defined($info), 'info returned';
        is $info->{basename}, 'testdir', 'basename (no trailing slash)';
        ok $info->{is_dir}, 'is directory';
        is $info->{size}, 0, 'size is 0';
    };

    subtest 'nonexistent entry' => sub {
        my $info = $reader->get_entry_info('nonexistent.txt');
        is $info, undef, 'returns undef for nonexistent entry';
    };

    subtest 'root has no info' => sub {
        my $info = $reader->get_entry_info('');
        is $info, undef, 'returns undef for root';
    };
};

subtest 'UTF-8 handling' => sub {
    my $tempdir = tempdir;
    use Unicode::Normalize qw(NFD NFC);
    use Encode qw(encode_utf8);

    # Create tar.gz with NFD filename (encoded as bytes for Archive::Tar)
    my $tar = Archive::Tar->new();
    my $nfd_filename = NFD('ポ') . '.txt';    # ポ in NFD = U+30DB + U+309A
    my $nfd_bytes = encode_utf8($nfd_filename);
    $tar->add_data($nfd_bytes, 'content');
    my $tar_gz_path = $tempdir->child('test.tar.gz');
    die "Failed to write tar.gz" unless $tar->write($tar_gz_path->stringify, COMPRESS_GZIP);

    my $reader = DoubleDrive::Archive::Reader::TarGz->new(archive_path => $tar_gz_path);
    my $entries = $reader->list_entries('');

    # basename should be NFC normalized
    my $expected_nfc = NFC('ポ') . '.txt';    # ポ in NFC = U+30DD
    is $entries->[0]{basename}, $expected_nfc, 'NFD -> NFC normalized';
    ok utf8::is_utf8($entries->[0]{basename}), 'basename is internal string';
};

subtest 'tgz extension' => sub {
    my $tempdir = tempdir;
    my $tgz_path = create_test_tar_gz(
        $tempdir,
        'test.tgz',
        [
            { type => 'file', path => 'file.txt', content => 'test' },
        ]
    );

    my $reader = DoubleDrive::Archive::Reader::TarGz->new(archive_path => $tgz_path);
    my $entries = $reader->list_entries('');

    is scalar(@$entries), 1, 'tgz file reads correctly';
    is $entries->[0]{basename}, 'file.txt', 'correct entry';
};

done_testing;
