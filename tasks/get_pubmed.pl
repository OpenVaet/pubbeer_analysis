use strict;
use 5.26.0;
no autovivification;
use warnings;
binmode STDOUT, ":utf8";
use utf8;
use LWP::UserAgent;
use HTTP::Cookies;
use HTML::Tree;
use Encode qw(decode);
use DBI;
use Time::Piece;
use DateTime;
use JSON;
use Data::Printer;
use Math::Round qw(nearest);
use Log::Log4perl qw(:easy);
use WWW::Mechanize::Chrome;
use FindBin;
use lib "$FindBin::Bin/../lib";
use global;

my $max_attempts                  = 5;

my %pubmed_dates                  = ();
my %pubmed_publications           = ();
my $latest_pubmed_publication_id  = 0;

load_pubmed_publications();

sub load_pubmed_publications {
    my $tb = $dbh->selectall_hashref("SELECT id as pubmed_publication_id, creation_date, pubmed_id FROM pubmed_publication WHERE id > $latest_pubmed_publication_id", 'pubmed_publication_id') or die $!;
    for my $pubmed_publication_id (sort{$a <=> $b} keys %$tb) {
        $latest_pubmed_publication_id = $pubmed_publication_id;
        my $creation_date = %$tb{$pubmed_publication_id}->{'creation_date'} // die;
        my $pubmed_id     = %$tb{$pubmed_publication_id}->{'pubmed_id'}     // die;
        $pubmed_publications{$pubmed_id}->{'pubmed_publication_id'} = $pubmed_publication_id;
        $pubmed_dates{$creation_date} = 1;
    }
}

# Configures UA.
my $ua = LWP::UserAgent->new;
$ua->agent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.159 Safari/537.36');
$ua->timeout(10);
my $cookie_jar = HTTP::Cookies->new(
    file     => "cookies.txt",      # File to store the cookies
    autosave => 1,                  # Save cookies automatically
    ignore_discard => 1             # Keep session cookies
);
$ua->cookie_jar($cookie_jar);

my $date  = DateTime->new(
    year      => 1970,
    month     => 1,
    day       => 1,
    time_zone => 'local',
);

my $today = DateTime->today( time_zone => 'local' );

while ( $date <= $today ) {
    
    my $ymd = $date->ymd('-');
    if (!exists $pubmed_dates{$ymd}) {

	    my ($y, $m, $d) = split '-', $ymd;
	    my $page_num = 1;
	    my $max_page = 999;
	    while ($page_num <= $max_page) {
	    	STDOUT->printflush("\rDownloading publications - [$ymd] - [$page_num / $max_page]        ");
			my $url      = 'https://pubmed.ncbi.nlm.nih.gov/?term=((%22' . $y . '%2F' . $m . '%2F' . $d . '%22%5BDate%20-%20Create%5D%20%3A%20%22' . $y . '%2F' . $m . '%2F' . $d . '%22%5BDate%20-%20Create%5D))&filter=hum_ani.humans&filter=other.excludepreprints&page=' . $page_num;
			my ($success, $attempts) = (0, 0);
			my $response;
			while (!$success && $attempts <= $max_attempts) {
				$attempts++;
				$response = $ua->get($url);
				if ($response->is_success) {
					my $content   = $response->decoded_content;
					my $tree      = HTML::Tree->new();
					$tree->parse($content);
					if ($tree->look_down(class=>"search-results-chunk results-chunk")) {
						$success = 1;
					}
				} else {
					say "\nFailed to get [$url]. Sleeping 2 seconds & retrying";
					sleep 2;
				}
			}
			my $content   = $response->decoded_content;
			my $tree      = HTML::Tree->new();
			$tree->parse($content);
			my $div_chunk = $tree->look_down(class=>"search-results-chunk results-chunk");
			last unless $div_chunk;
			$max_page     = $div_chunk->attr_get_i('data-max-page');
			my @docsums   = $tree->look_down(class=>"docsum-wrap");
			for my $docsum (@docsums) {
				my $span_pmid = $docsum->look_down(class=>"docsum-pmid");
				my $pmid = $span_pmid->as_trimmed_text;
				unless (exists $pubmed_publications{$pmid}->{'pubmed_publication_id'}) {
					my $sth = $dbh->prepare("INSERT INTO pubmed_publication (creation_date, pubmed_id) VALUES (?, ?)");
					$sth->execute($ymd, $pmid) or die $sth->err();
					load_pubmed_publications();
				}
			}
			$page_num++;
	    }
    }

    $date->add( days => 1 );
}