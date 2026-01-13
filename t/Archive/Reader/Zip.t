use v5.42;
use utf8;
use Test2::V0;
use POSIX qw(tzset);
use Path::Tiny qw(path tempdir);
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);

use lib 'lib';
use DoubleDrive::Archive::Reader::Zip;

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

subtest 'Zip reader construction' => sub {
    subtest 'reads valid zip file' => sub {
        my $tempdir = tempdir;
        my $zip_path = create_test_zip(
            $tempdir,
            'test.zip',
            [
                { type => 'file', path => 'file.txt', content => 'test' },
            ]
        );

        my $reader = DoubleDrive::Archive::Reader::Zip->new(archive_path => $zip_path);
        ok defined($reader), 'reader created';
        ok $reader isa 'DoubleDrive::Archive::Reader::Zip', 'is Zip reader';
    };

    subtest 'fails on invalid zip' => sub {
        my $tempdir = tempdir;
        my $invalid_file = $tempdir->child('invalid.zip');
        $invalid_file->spew("not a zip file");

        like dies { DoubleDrive::Archive::Reader::Zip->new(archive_path => $invalid_file) },
            qr/Failed to read ZIP archive/,
            'dies on invalid zip';
    };
};

subtest 'list_entries - root level' => sub {
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

    my $reader = DoubleDrive::Archive::Reader::Zip->new(archive_path => $zip_path);
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
    my $zip_path = create_test_zip(
        $tempdir,
        'test.zip',
        [
            { type => 'file', path => 'dir/file.txt', content => 'nested' },
            { type => 'file', path => 'dir/subdir/deep.txt', content => 'deep' },
        ]
    );

    my $reader = DoubleDrive::Archive::Reader::Zip->new(archive_path => $zip_path);
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
    my $zip_path = create_test_zip(
        $tempdir,
        'test.zip',
        [
            { type => 'file', path => 'a/b/c/deep.txt', content => 'very deep' },
        ]
    );

    my $reader = DoubleDrive::Archive::Reader::Zip->new(archive_path => $zip_path);

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
    my $zip_path = create_test_zip(
        $tempdir,
        'test.zip',
        [
            { type => 'file', path => 'test.txt', content => 'hello world', mtime => $mtime },
            { type => 'dir', path => 'testdir/', mtime => $mtime },
        ]
    );

    my $reader = DoubleDrive::Archive::Reader::Zip->new(archive_path => $zip_path);

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

    # Create ZIP with NFD filename (encoded as bytes for Archive::Zip)
    my $zip = Archive::Zip->new();
    my $nfd_filename = NFD('ポ') . '.txt';    # ポ in NFD = U+30DB + U+309A
    my $nfd_bytes = encode_utf8($nfd_filename);
    $zip->addString('content', $nfd_bytes);
    my $zip_path = $tempdir->child('test.zip');
    die "Failed to write ZIP" unless $zip->writeToFileNamed($zip_path->stringify) == AZ_OK;

    my $reader = DoubleDrive::Archive::Reader::Zip->new(archive_path => $zip_path);
    my $entries = $reader->list_entries('');

    # basename should be NFC normalized
    my $expected_nfc = NFC('ポ') . '.txt';    # ポ in NFC = U+30DD
    is $entries->[0]{basename}, $expected_nfc, 'NFD -> NFC normalized';
    ok utf8::is_utf8($entries->[0]{basename}), 'basename is internal string';
};

done_testing;
