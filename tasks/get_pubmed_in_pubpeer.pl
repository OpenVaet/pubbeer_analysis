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
my %publications                  = ();
my $latest_publication_id         = 0;
my %journals                      = ();
my $latest_journal_id             = 0;
my %authors                       = ();
my $latest_author_id              = 0;
my %author_publications           = ();
my $latest_author_publication_id  = 0;
my %journal_publications          = ();
my $latest_journal_publication_id = 0;

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

load_pubmed_publications();

load_publications();

load_journals();

load_authors();

load_author_publications();

load_journal_publications();

# Fetching token.
my $token   = fetch_token();
my $current = 0;
my $total   = keys %pubmed_publications;
for my $pubmed_id (sort keys %pubmed_publications) {
    $current++;
    STDOUT->printflush("\rIdentifying publications from PubMed to PubPeer - [$current / $total]");
    my $url      = "https://pubpeer.com/api/search/?q=$pubmed_id&token=$token";
    my ($success, $attempts) = (0, 0);
    my $response;
    while (!$success && $attempts <= $max_attempts) {
        $attempts++;
        $response = $ua->get($url);
        if ($response->is_success) {
            $success = 1;
        } else {
            say "\nFailed to get [$url]. Sleeping 2 seconds & retrying";
            sleep 2;
        }
    }
    my $content  = $response->decoded_content;
    my $json     = decode_json($content);
    my $found    = parse_publications($pubmed_id, $json);
    my $pubmed_publication_id = $pubmed_publications{$pubmed_id}->{'pubmed_publication_id'} // die;
    my $sth = $dbh->prepare("UPDATE pubmed_publication SET verified = 1, found = $found, verification_timestamp = UNIX_TIMESTAMP() WHERE id = $pubmed_publication_id");
    $sth->execute() or die $sth->err();
}

sub load_pubmed_publications {
    my $tb = $dbh->selectall_hashref("SELECT id as pubmed_publication_id, creation_date, pubmed_id FROM pubmed_publication WHERE verified = 0", 'pubmed_publication_id') or die $!;
    for my $pubmed_publication_id (sort{$a <=> $b} keys %$tb) {
        my $creation_date   = %$tb{$pubmed_publication_id}->{'creation_date'}   // die;
        my $pubmed_id       = %$tb{$pubmed_publication_id}->{'pubmed_id'}       // die;
        $pubmed_publications{$pubmed_id}->{'pubmed_publication_id'} = $pubmed_publication_id;
        $pubmed_dates{$creation_date} = 1;
    }
}

sub load_publications {
    my $tb = $dbh->selectall_hashref("SELECT id as publication_id, pubpeer_id, comments_total, comments_updated, link_with_hash, updated, pubmed_id FROM publication WHERE id > $latest_publication_id", 'publication_id') or die $!;
    for my $publication_id (sort{$a <=> $b} keys %$tb) {
        $latest_publication_id = $publication_id;
        my $pubpeer_id       = %$tb{$publication_id}->{'pubpeer_id'}       // die;
        my $pubmed_id        = %$tb{$publication_id}->{'pubmed_id'};
        my $comments_total   = %$tb{$publication_id}->{'comments_total'}   // die;
        my $comments_updated = %$tb{$publication_id}->{'comments_updated'} // die;
        my $link_with_hash   = %$tb{$publication_id}->{'link_with_hash'}   // die;
        my $updated          = %$tb{$publication_id}->{'updated'}          // die;
        $publications{$pubpeer_id}->{'publication_id'}   = $publication_id;
        $publications{$pubpeer_id}->{'comments_total'}   = $comments_total;
        $publications{$pubpeer_id}->{'comments_updated'} = $comments_updated;
        $publications{$pubpeer_id}->{'link_with_hash'}   = $link_with_hash;
        $publications{$pubpeer_id}->{'updated'}          = $updated;
        $publications{$pubpeer_id}->{'pubmed_id'}        = $pubmed_id;
    }
}

sub load_journals {
    my $tb = $dbh->selectall_hashref("SELECT id as journal_id, pubpeer_id, issn, title FROM journal WHERE id > $latest_journal_id", 'journal_id') or die $!;
    for my $journal_id (sort{$a <=> $b} keys %$tb) {
        $latest_journal_id = $journal_id;
        my $pubpeer_id = %$tb{$journal_id}->{'pubpeer_id'} // die;
        my $issn       = %$tb{$journal_id}->{'issn'};
        my $title      = %$tb{$journal_id}->{'title'}      // die;
        $journals{$pubpeer_id}->{'journal_id'} = $journal_id;
        $journals{$pubpeer_id}->{'issn'}       = $issn;
        $journals{$pubpeer_id}->{'title'}      = $title;
    }
}

sub load_authors {
    my $tb = $dbh->selectall_hashref("SELECT id as author_id, pubpeer_id, first_name, last_name, email FROM author WHERE id > $latest_author_id", 'author_id') or die $!;
    for my $author_id (sort{$a <=> $b} keys %$tb) {
        $latest_author_id = $author_id;
        my $pubpeer_id = %$tb{$author_id}->{'pubpeer_id'} // die;
        my $first_name = %$tb{$author_id}->{'first_name'} // die;
        my $last_name  = %$tb{$author_id}->{'last_name'}  // die;
        my $email      = %$tb{$author_id}->{'email'};
        $authors{$pubpeer_id}->{'author_id'}  = $author_id;
        $authors{$pubpeer_id}->{'first_name'} = $first_name;
        $authors{$pubpeer_id}->{'last_name'}  = $last_name;
        $authors{$pubpeer_id}->{'email'}      = $email;
    }
}

sub load_author_publications {
    my $tb = $dbh->selectall_hashref("SELECT id as author_publication_id, author_id, publication_id FROM author_publication WHERE id > $latest_author_publication_id", 'author_publication_id') or die $!;
    for my $author_publication_id (sort{$a <=> $b} keys %$tb) {
        $latest_author_publication_id = $author_publication_id;
        my $author_id = %$tb{$author_publication_id}->{'author_id'} // die;
        my $publication_id = %$tb{$author_publication_id}->{'publication_id'} // die;
        $author_publications{$author_id}->{$publication_id}->{'author_publication_id'} = $author_publication_id;
    }
}

sub load_journal_publications {
    my $tb = $dbh->selectall_hashref("SELECT id as journal_publication_id, journal_id, publication_id FROM journal_publication WHERE id > $latest_journal_publication_id", 'journal_publication_id') or die $!;
    for my $journal_publication_id (sort{$a <=> $b} keys %$tb) {
        $latest_journal_publication_id = $journal_publication_id;
        my $journal_id = %$tb{$journal_publication_id}->{'journal_id'} // die;
        my $publication_id = %$tb{$journal_publication_id}->{'publication_id'} // die;
        $journal_publications{$journal_id}->{$publication_id}->{'journal_publication_id'} = $journal_publication_id;
    }
}

sub fetch_token {
    my $first_pmed_id;
    for my $pubmed_id (sort keys %pubmed_publications) {
        $first_pmed_id = $pubmed_id;
        last;
    }
    my $url      = "https://pubpeer.com/search?q=$first_pmed_id";
    my $response = $ua->get($url);
    die unless ($response->is_success);
    my $content  = $response->decoded_content;
    my $tree     = HTML::Tree->new();
    $tree->parse($content);
    my $token = $tree->look_down(name=>"csrf-token");
    $token = $token->attr_get_i('content');
    die unless $token;
    return $token;
}

sub parse_publications {
    my ($pubmed_id, $json) = @_;
    my $found = 0;
    return 0 unless %$json{'publications'};
    for my $publication_data (@{%$json{'publications'}}) {
        $found++;
        my $publication_pubpeer_id = %$publication_data{'id'}                  // die;
        my $created                = %$publication_data{'created'}             // die;
        my $comments_total         = %$publication_data{'comments_total'}      // die;
        my $has_author_response    = %$publication_data{'has_author_response'};
        if ($has_author_response) {
            $has_author_response   = 1;
        } else {
            $has_author_response   = 0;
        }
        my $link_with_hash         = %$publication_data{'link_with_hash'}      // die;
        my $title                  = %$publication_data{'title'}               // die;
        my $updated                = %$publication_data{'updated'}             // die;
        $created                   = to_yyyy_mm_dd_hh_mm_ss($created);
        $updated                   = to_yyyy_mm_dd_hh_mm_ss($updated) if $updated;

        # Inserting publication data.
        unless ($publications{$publication_pubpeer_id}) {
            my $sth = $dbh->prepare("INSERT INTO publication (pubpeer_id, created, comments_total, has_author_response, link_with_hash, title, updated, pubmed_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
            $sth->execute($publication_pubpeer_id, $created, $comments_total, $has_author_response, $link_with_hash, $title, $updated, $pubmed_id) or die $sth->err();
            load_publications();
        }
        my $publication_id = $publications{$publication_pubpeer_id}->{'publication_id'} // die;
        if (!$publications{$publication_pubpeer_id}->{'comments_total'} && $comments_total ||
            ($publications{$publication_pubpeer_id}->{'comments_total'} && $comments_total && $comments_total ne $publications{$publication_pubpeer_id}->{'comments_total'})) {
            my $sth = $dbh->prepare("UPDATE publication SET comments_total = ? WHERE id = $publication_id");
            $sth->execute($comments_total) or die $sth->err(); 
        }
        if (!$publications{$publication_pubpeer_id}->{'pubmed_id'} && $pubmed_id ||
            ($publications{$publication_pubpeer_id}->{'pubmed_id'} && $pubmed_id && $pubmed_id ne $publications{$publication_pubpeer_id}->{'pubmed_id'})) {
            my $sth = $dbh->prepare("UPDATE publication SET pubmed_id = ? WHERE id = $publication_id");
            $sth->execute($pubmed_id) or die $sth->err(); 
        }

        # Inserting journals data.
        for my $journal_data (@{%$publication_data{'journals'}->{'data'}}) {
            my $journal_pubpeer_id = %$journal_data{'id'}        // die;
            my $issn               = %$journal_data{'issn'};
            my $journal_title      = %$journal_data{'title'}     // die;
            unless (exists $journals{$journal_pubpeer_id}) {
                my $sth = $dbh->prepare("INSERT INTO journal (pubpeer_id, issn, title) VALUES (?, ?, ?)");
                $sth->execute($journal_pubpeer_id, $issn, $journal_title) or die $sth->err();
                load_journals();
            }
            my $journal_id = $journals{$journal_pubpeer_id}->{'journal_id'} // die;
            if (!$journals{$journal_pubpeer_id}->{'issn'} && $issn ||
                ($journals{$journal_pubpeer_id}->{'issn'} && $issn && $issn ne $journals{$journal_pubpeer_id}->{'issn'})) {
                my $sth = $dbh->prepare("UPDATE journal SET issn = ? WHERE id = $journal_id");
                $sth->execute($issn) or die $sth->err(); 
            }

            # Verifying relation publication <-> journal.
            unless (exists $journal_publications{$journal_id}->{$publication_id}) {
                my $sth = $dbh->prepare("INSERT INTO journal_publication (journal_id, publication_id) VALUES (?, ?)");
                $sth->execute($journal_id, $publication_id) or die $sth->err();
                load_journal_publications();
            }
        }

        # Inserting authors data.
        for my $author_data (@{%$publication_data{'authors'}->{'data'}}) {
            my $author_pubpeer_id  = %$author_data{'id'}         // die;
            my $first_name         = %$author_data{'first_name'} // die;
            my $last_name          = %$author_data{'last_name'}  // die;
            my $email              = %$author_data{'email'};
            $email = undef unless $email;
            unless (exists $authors{$author_pubpeer_id}) {
                my $sth = $dbh->prepare("INSERT INTO author (pubpeer_id, first_name, last_name, email) VALUES (?, ?, ?, ?)");
                $sth->execute($author_pubpeer_id, $first_name, $last_name, $email) or die $sth->err();
                load_authors();
            }
            my $author_id = $authors{$author_pubpeer_id}->{'author_id'} // die;
            if (!$authors{$author_pubpeer_id}->{'email'} && $email ||
                ($authors{$author_pubpeer_id}->{'email'} && $email && $email ne $authors{$author_pubpeer_id}->{'email'})) {
                my $sth = $dbh->prepare("UPDATE author SET email = ? WHERE id = $author_id");
                $sth->execute($email) or die $sth->err(); 
            }

            # Verifying relation publication <-> author.
            unless (exists $author_publications{$author_id}->{$publication_id}) {
                my $sth = $dbh->prepare("INSERT INTO author_publication (author_id, publication_id) VALUES (?, ?)");
                $sth->execute($author_id, $publication_id) or die $sth->err();
                load_author_publications();
            }
        }
    }
    return $found;
}

sub to_yyyy_mm_dd_hh_mm_ss {
    my ($input) = @_;
    my $t = Time::Piece->strptime(
        $input,
        '%a, %b %e, %Y %I:%M %p'
    );
    return $t->strftime('%Y-%m-%d %H:%M:%S');
}
