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
use JSON;
use Data::Printer;
use Math::Round qw(nearest);
use Log::Log4perl qw(:easy);
use WWW::Mechanize::Chrome;
use FindBin;
use lib "$FindBin::Bin/../lib";
use global;

my $url_base                      = "https://pubpeer.com";
my $recent_ext                    = "/api/recent/from/";

my $max_attempts                  = 5;

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

load_publications();

load_journals();

load_authors();

load_author_publications();

load_journal_publications();

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

# Recursive sorting function for deep sorting of nested hashes
sub deep_sort {
    my ($hash) = @_;
    return {
        map {
            my $key = $_;
            $key => ref $hash->{$key} eq 'HASH'
                    ? deep_sort($hash->{$key})  # Recursively sort if value is a hash
                    : $hash->{$key};            # Otherwise, return the value as is
        } sort keys %$hash                      # Sort the keys of the current hash
    };
}

# Archiving.
my $url      = $url_base . '/api/recent';
my $response = $ua->get($url);
die unless ($response->is_success);
my $content  = $response->decoded_content;
my $json     = decode_json($content);
my $total_publications = %$json{'meta'}->{'total'} // die;
parse_publications($json);
my $from = 40;
while ($from < $total_publications) {
    STDOUT->printflush("\rDownloading publications - [$from / $total_publications]");
    my $url      = $url_base . $recent_ext . $from;
    my $response = $ua->get($url);
    last unless ($response->is_success);
    # die unless ($response->is_success); # Should be a "die" but bug.
    my $content  = $response->decoded_content;
    my $json     = decode_json($content);
    my $total_publications = %$json{'meta'}->{'total'} // die;
    parse_publications($json);
    $from += 40;
}
say "";

my $cookie = HTTP::Cookies->new();
Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR
my $mech = WWW::Mechanize::Chrome->new(
    headless   => 0,
    timeout    => 30,
    cookie_jar => $cookie,
    sync       => 1
);

# Fetching articles which have comments which haven't been updated yet.
my ($current, $total) = (0, 0);
for my $publication_pubpeer_id (keys  %publications) {
    my $comments_total   = $publications{$publication_pubpeer_id}->{'comments_total'}   // die;
    my $comments_updated = $publications{$publication_pubpeer_id}->{'comments_updated'} // die;
    if ($comments_total != $comments_updated) {
        $total++;
    }
}
for my $publication_pubpeer_id (keys  %publications) {
    my $comments_total   = $publications{$publication_pubpeer_id}->{'comments_total'}   // die;
    my $comments_updated = $publications{$publication_pubpeer_id}->{'comments_updated'} // die;
    if ($comments_total != $comments_updated) {
        $current++;
        my $link_with_hash = $publications{$publication_pubpeer_id}->{'link_with_hash'} // die;
        my $url            = $url_base . $link_with_hash;
        say "url : $url";
        $mech->get($url);
        my $content;
        my ($parsing_success, $parsing_attempts) = (0, 0);
        while ($parsing_success == 0) {
            $parsing_attempts++;
            eval {
                $content = $mech->content();
            };
            if ($@) {
                say "failed recovering content from page on [$url] (node error)";
                if ($parsing_attempts > $max_attempts) {
                    say "giving up on this page ...";
                    return {};
                }
            } else {
                $parsing_success = 1;
            }
        }
        my $tree           = HTML::Tree->new();
        $tree->parse($content);
        open my $out, '>', 'tmp.html';
        print $out $tree->as_HTML("<>&", "\t");
        close $out;
        die;
    }
}

sub load_publications {
    my $tb = $dbh->selectall_hashref("SELECT id as publication_id, pubpeer_id, comments_total, comments_updated, link_with_hash, updated FROM publication WHERE id > $latest_publication_id", 'publication_id') or die $!;
    for my $publication_id (sort{$a <=> $b} keys %$tb) {
        $latest_publication_id = $publication_id;
        my $pubpeer_id       = %$tb{$publication_id}->{'pubpeer_id'}       // die;
        my $comments_total   = %$tb{$publication_id}->{'comments_total'}   // die;
        my $comments_updated = %$tb{$publication_id}->{'comments_updated'} // die;
        my $link_with_hash   = %$tb{$publication_id}->{'link_with_hash'}   // die;
        my $updated          = %$tb{$publication_id}->{'updated'}          // die;
        $publications{$pubpeer_id}->{'publication_id'}   = $publication_id;
        $publications{$pubpeer_id}->{'comments_total'}   = $comments_total;
        $publications{$pubpeer_id}->{'comments_updated'} = $comments_updated;
        $publications{$pubpeer_id}->{'link_with_hash'}   = $link_with_hash;
        $publications{$pubpeer_id}->{'updated'}          = $updated;
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

sub parse_publications {
    my $json = shift;
    for my $publication_data (@{%$json{'publications'}}) {
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
            my $sth = $dbh->prepare("INSERT INTO publication (pubpeer_id, created, comments_total, has_author_response, link_with_hash, title, updated) VALUES (?, ?, ?, ?, ?, ?, ?)");
            $sth->execute($publication_pubpeer_id, $created, $comments_total, $has_author_response, $link_with_hash, $title, $updated) or die $sth->err();
            load_publications();
        }
        my $publication_id = $publications{$publication_pubpeer_id}->{'publication_id'} // die;
        if (!$publications{$publication_pubpeer_id}->{'comments_total'} && $comments_total ||
            ($publications{$publication_pubpeer_id}->{'comments_total'} && $comments_total && $comments_total ne $publications{$publication_pubpeer_id}->{'comments_total'})) {
            my $sth = $dbh->prepare("UPDATE publication SET comments_total = ? WHERE id = $publication_id");
            $sth->execute($comments_total) or die $sth->err(); 
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
}

sub to_yyyy_mm_dd_hh_mm_ss {
    my ($input) = @_;
    my $t = Time::Piece->strptime(
        $input,
        '%a, %b %e, %Y %I:%M %p'
    );
    return $t->strftime('%Y-%m-%d %H:%M:%S');
}
