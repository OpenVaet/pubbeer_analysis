#!/usr/bin/env perl
use strict;
use warnings;
use 5.016;

use HTTP::Tiny;
use File::Path qw(make_path);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use XML::Twig;
use Proc::Background;                 ### NEW
use Getopt::Long qw(GetOptions);      ### NEW

# Required non-core module: XML::Twig (cpan install XML::Twig)
# Core modules: HTTP::Tiny, File::Path, IO::Uncompress::Gunzip, Getopt::Long, Proc::Background

my $base_url   = 'https://ftp.ncbi.nlm.nih.gov/pubmed/baseline/';
my $raw_dir    = 'data/pubmed_raw';
my $xml_dir    = 'data/pubmed';
my $ids_dir    = 'data/pubmed_ids';
my $pmid_file  = 'data/pubmed_ids.txt';
my $cache_dir  = 'data/cache';        ### NEW

my $worker_id;                        ### NEW
my $worker_total;                     ### NEW

GetOptions(                           ### NEW
    'worker=i'  => \$worker_id,
    'workers=i' => \$worker_total,
) or die "Usage: $0 [--worker N --workers M]\n";

my $is_worker = defined $worker_id && defined $worker_total && $worker_total > 0;  ### NEW

make_path($raw_dir, $xml_dir, $ids_dir, $cache_dir);

########################################################################
# If this is a worker process, skip download & gunzip and ONLY parse.
########################################################################

if ($is_worker) {                     ### NEW
    print "Worker $worker_id/$worker_total starting parsing...\n";
    parse_pending_for_worker($worker_id, $worker_total, $xml_dir, $ids_dir);
    print "Worker $worker_id finished.\n";
    exit 0;
}

########################################################################
# ORCHESTRATOR: Steps 1 & 2 are unchanged (download + gunzip)
########################################################################

# 1. Download all .gz files from the baseline directory
my $http = HTTP::Tiny->new( verify_SSL => 1 );

print "Fetching directory listing...\n";
my $res = $http->get($base_url);
die "Failed to fetch $base_url: $res->{status} $res->{reason}\n"
    unless $res->{success};

my $html = $res->{content};

# Extract all .gz file names (e.g. pubmed25n0001.xml.gz)
my @gz_files = grep {
    /^pubmed/ && /\.gz$/
} ($html =~ m{href="([^"]+)"}gi);

die "No .gz files found in listing, pattern may need updating\n"
    unless @gz_files;

for my $file (@gz_files) {
    my $url  = $base_url . $file;
    my $dest = "$raw_dir/$file";

    if (-e $dest) {
        print "Already downloaded: $file\n";
        next;
    }

    print "Downloading $file ...\n";
    my $r = $http->mirror($url, $dest);
    die "Download failed for $url: $r->{status} $r->{reason}\n"
        unless $r->{success} || $r->{status} == 304;
}

# 2. Extract all .gz files into data/pubmed
opendir my $raw_dh, $raw_dir or die "Cannot open $raw_dir: $!\n";
while (my $entry = readdir $raw_dh) {
    next unless $entry =~ /\.gz$/;

    my $src = "$raw_dir/$entry";
    (my $xml_name = $entry) =~ s/\.gz$//;
    my $dst = "$xml_dir/$xml_name";

    if (-e $dst) {
        print "Already extracted: $xml_name\n";
        next;
    }

    print "Decompressing $entry ...\n";
    gunzip $src => $dst
        or die "gunzip failed for $src: $GunzipError\n";
}
closedir $raw_dh;

########################################################################
# 3. ORCHESTRATOR: decide which XMLs are left, split into 4 batches,
#    write counts into data/cache, then launch 4 background workers.
########################################################################

my $num_workers = 4;

opendir my $xml_dh, $xml_dir or die "Cannot open $xml_dir: $!\n";
my @all_xml = sort grep { /\.xml$/ } readdir $xml_dh;
closedir $xml_dh;

my @counts = (0) x $num_workers;
my $idx = 0;

for my $file (@all_xml) {
    (my $csv_name = $file) =~ s/\.xml$/.csv/;
    my $csv_path = "$ids_dir/$csv_name";

    # We still increment idx for every XML so that worker assignment
    # (idx % num_workers) is deterministic, but only count those without CSV.
    my $assigned_worker = $idx % $num_workers;   # 0..3
    if (! -e $csv_path) {
        $counts[$assigned_worker]++;
    }
    $idx++;
}

my $total_pending = 0;
$total_pending += $_ for @counts;
print "Total XML files left to process: $total_pending\n";

for my $i (0 .. $num_workers-1) {
    my $wid        = $i + 1;
    my $count      = $counts[$i];
    my $cache_file = "$cache_dir/worker_${wid}_count.txt";

    open my $cfh, '>', $cache_file
        or die "Cannot open $cache_file for writing: $!\n";
    print {$cfh} "$count\n";
    close $cfh;

    print "Worker $wid will process $count files\n";
}

print "Starting $num_workers background workers for XML parsing...\n";
my @procs;
for my $wid (1 .. $num_workers) {
    my $proc = Proc::Background->new(
        $^X, $0, '--worker', $wid, '--workers', $num_workers
    );
    push @procs, $proc;
}

# Wait for all workers to finish
$_->wait() for @procs;

########################################################################
# 4. Concatenate all per-file CSVs into the final result file
########################################################################

open my $pmid_fh, '>', $pmid_file
    or die "Cannot open $pmid_file for writing: $!\n";

opendir my $ids_dh, $ids_dir or die "Cannot open $ids_dir: $!\n";

# Optional: sort for deterministic order
my @csv_files = sort grep { /\.csv$/ } readdir $ids_dh;
closedir $ids_dh;

for my $csv (@csv_files) {
    my $path = "$ids_dir/$csv";

    open my $in_fh, '<', $path
        or die "Cannot open $path for reading: $!\n";

    while (my $line = <$in_fh>) {
        print {$pmid_fh} $line;
    }
    close $in_fh;
}

close $pmid_fh;

print "Done. Per-XML PMIDs in $ids_dir/*.csv; aggregated PMIDs written to $pmid_file\n";

########################################################################
# Subroutines
########################################################################

sub parse_pending_for_worker {
    my ($worker_id, $worker_total, $xml_dir, $ids_dir) = @_;

    opendir my $xml_dh, $xml_dir or die "Worker $worker_id: Cannot open $xml_dir: $!\n";
    my @all_xml = sort grep { /\.xml$/ } readdir $xml_dh;
    closedir $xml_dh;

    my $idx = 0;

    for my $file (@all_xml) {
        my $assigned_worker = ($idx % $worker_total) + 1;  # 1..$worker_total
        $idx++;

        # Only handle files assigned to this worker
        next unless $assigned_worker == $worker_id;

        my $xml_path = "$xml_dir/$file";
        (my $csv_name = $file) =~ s/\.xml$/.csv/;
        my $csv_path = "$ids_dir/$csv_name";

        if (-e $csv_path) {
            print "Worker $worker_id: already processed: $file (found $csv_name)\n";
            next;
        }

        print "Worker $worker_id: parsing $file -> $csv_name ...\n";

        open my $csv_fh, '>', $csv_path
            or die "Worker $worker_id: Cannot open $csv_path for writing: $!\n";

        my $twig = XML::Twig->new(
            twig_handlers => {
                # Match: <ArticleId IdType="pubmed">23510</ArticleId>
                'ArticleId' => sub {
                    my ($twig, $elt) = @_;
                    return unless ($elt->att('IdType') || '') eq 'pubmed';
                    my $pmid = $elt->text;
                    print {$csv_fh} "$pmid\n";  # one PMID per line
                    $elt->purge;                # free memory as we go
                },
            },
            keep_encoding => 1,
        );

        $twig->parsefile($xml_path);
        $twig->purge;
        close $csv_fh;
    }
}
