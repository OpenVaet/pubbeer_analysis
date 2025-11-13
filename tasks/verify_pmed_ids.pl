use strict;
use 5.26.0;
no autovivification;
use warnings;
binmode STDOUT, ":utf8";
use utf8;
use Encode qw(decode);
use DBI;
use Time::Piece;
use DateTime;
use JSON;
use Data::Printer;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../lib";
use global;

my %pubmed_publications = ();

load_pubmed_publications();

my %pubmed_ids_list     = ();

load_pubmed_ids_list();

sub load_pubmed_ids_list {
    open my $in, '<', 'data/id_list.txt';
    while (<$in>) {
        chomp $_;
        $pubmed_ids_list{$_} = 1;
    }
    close $in;
}

sub load_pubmed_publications {
    my $tb = $dbh->selectall_hashref("SELECT id as pubmed_publication_id, creation_date, pubmed_id FROM pubmed_publication WHERE verified = 0", 'pubmed_publication_id') or die $!;
    for my $pubmed_publication_id (sort{$a <=> $b} keys %$tb) {
        my $creation_date   = %$tb{$pubmed_publication_id}->{'creation_date'}   // die;
        my $pubmed_id       = %$tb{$pubmed_publication_id}->{'pubmed_id'}       // die;
        unless (exists $pubmed_ids_list{$pubmed_id}) {
            say "Not found in the IDs file : [$pubmed_id]";
        }
    }
}