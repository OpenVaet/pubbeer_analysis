#!/usr/bin/env perl
use strict;
use 5.26.0;
no autovivification;
use warnings;
binmode STDOUT, ":utf8";
use utf8;

use LWP::UserAgent;
use HTTP::Cookies;
use HTML::Tree;
use JSON;
use IO::Handle;

my $max_attempts = 5;
$| = 1; # autoflush STDOUT

# -------------------------------------------------------------------
# Arguments: input_file (PubMed IDs) output_file (JSONL results)
# -------------------------------------------------------------------
my $input_file  = $ARGV[0] // die "Usage: $0 input_file output_file\n";
my $output_file = $ARGV[1] // die "Usage: $0 input_file output_file\n";

# -------------------------------------------------------------------
# Read PubMed IDs from input file
# -------------------------------------------------------------------
my @pubmed_ids;
{
    open my $in, '<:encoding(UTF-8)', $input_file
        or die "Can't open input file [$input_file]: $!";

    while (my $line = <$in>) {
        chomp $line;
        $line =~ s/\r//g;
        next unless $line =~ /\S/;
        push @pubmed_ids, $line;
    }
    close $in;
}

die "No PubMed IDs found in [$input_file]\n" unless @pubmed_ids;

# -------------------------------------------------------------------
# Configure UserAgent + cookies
# Each worker uses its own cookie file to avoid races.
# -------------------------------------------------------------------
my $ua = LWP::UserAgent->new;
$ua->agent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.159 Safari/537.36');
$ua->timeout(10);

my $cookie_jar = HTTP::Cookies->new(
    file           => "cookies_pubpeer_$$.txt",
    autosave       => 1,
    ignore_discard => 1
);
$ua->cookie_jar($cookie_jar);

# -------------------------------------------------------------------
# Fetch CSRF token once for this worker
# -------------------------------------------------------------------
my $token = fetch_token($pubmed_ids[0]);

# -------------------------------------------------------------------
# Process all PubMed IDs and write JSONL to output_file
# -------------------------------------------------------------------
open my $out, '>:encoding(UTF-8)', $output_file
    or die "Can't open output file [$output_file]: $!";

my $total   = scalar @pubmed_ids;
my $current = 0;

for my $pubmed_id (@pubmed_ids) {
    $current++;
    print "\rWorker $$ processing PubMed [$pubmed_id] ($current / $total)";

    my $url = "https://pubpeer.com/api/search/?q=$pubmed_id&token=$token";

    my ($success, $attempts) = (0, 0);
    my $response;

    while (!$success && $attempts < $max_attempts) {
        $attempts++;
        $response = $ua->get($url);

        if ($response->is_success) {
            $success = 1;
        } else {
            warn "\n[$$] Failed to get [$url] ("
                . $response->status_line
                . ") attempt $attempts / $max_attempts\n";
            sleep 2 if $attempts < $max_attempts;
        }
    }

    my $record = {
        pubmed_id => $pubmed_id,
        success   => $success ? JSON::true : JSON::false,
        attempts  => $attempts,
    };

    if ($response) {
        $record->{'http_code'} = $response->code;
        $record->{'error'}     = $success ? undef : $response->status_line;
        $record->{'body'}      = $response->decoded_content;
    } else {
        $record->{'http_code'} = undef;
        $record->{'error'}     = "No HTTP response object";
        $record->{'body'}      = undef;
    }

    # One JSON object per line (JSONL)
    print {$out} encode_json($record), "\n";
}

print "\nWorker $$ done. Results written to [$output_file]\n";

close $out;
exit 0;

# -------------------------------------------------------------------
# fetch_token: grabs CSRF token from the HTML search page
# -------------------------------------------------------------------
sub fetch_token {
    my ($sample_pubmed_id) = @_;
    die "fetch_token() needs a sample PubMed ID\n" unless $sample_pubmed_id;

    my $url      = "https://pubpeer.com/search?q=$sample_pubmed_id";
    my $response = $ua->get($url);

    die "Failed to fetch token from [$url]: " . $response->status_line
        unless $response->is_success;

    my $content  = $response->decoded_content;
    my $tree     = HTML::Tree->new();
    $tree->parse($content);

    my $token_node = $tree->look_down(name => "csrf-token")
        or die "Could not find csrf-token meta tag on [$url]\n";

    my $token = $token_node->attr_get_i('content')
        or die "csrf-token meta tag has no content attribute\n";

    return $token;
}
