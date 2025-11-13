#!/usr/bin/perl

package global;

use strict;
use warnings;
use v5.14;
no autovivification;
use Data::Printer;
use JSON;
use DBI;
use Hash::Merge;
use Exporter; # Gain export capabilities 
use FindBin;
use lib "$FindBin::Bin/../lib";
use config;


# Exported variables & functions.
our (@EXPORT, @ISA);    # Global variables 
our $database_name        = $config{'database_name'} // die;
our $software_environment = $config{'environment'}  // die;
our $dbh                  = connect_dbi();
our %anteriorities        = ();

@ISA    = qw(Exporter); # Take advantage of Exporter's capabilities
@EXPORT = qw(
    set_anteriorities
	$database_name
	$software_environment
	$dbh
    %anteriorities
    deep_sort
);                      # Exported variables.

sub connect_dbi {
    die unless -f $config_file;
    my $config = do("./$config_file");
    $dbh =  DBI->connect(
          "DBI:mysql:database=" . $database_name . ";" .
                                "host=" . $config->{'database_host'} . ";port=" . $config->{'database_port'},
                                $config->{'database_user'}, $config->{'database_password'},
          { 
            mysql_enable_utf8 => 1,
            mysql_enable_utf8mb4 => 1,
            mysql_auto_reconnect => 1,
            AutoCommit => 1,
            RaiseError => 1,
            PrintError => 0,
          }
        ) || die $DBI::errstr;
    # Also sometimes helpful:
    $dbh->do("SET NAMES 'utf8mb4'");
    return $dbh;
}

sub set_anteriorities {
    my ($min_anteriority, $max_anteriority) = @_;
    my $ant = $max_anteriority;
    while ($ant >= $min_anteriority) {
        $anteriorities{$ant} = 1;
        my $minus = 10;
        if ($ant <= 30) {
            $minus = 5;
        } elsif ($ant <= 15) {
            $minus = 1;
        }
        $ant = $ant - $minus;
    }
    # p%anteriorities;
    # die;
}

# Recursive sorting function for deep sorting of nested hashes
sub deep_sort {
    my ($hash) = @_;

    return { 
        map {
            my $key = $_;
            $key => ref $hash->{$key} eq 'HASH' 
                    ? deep_sort($hash->{$key})  # Recursively sort if value is a hash
                    : $hash->{$key};  # Otherwise, return the value as is
        } sort keys %$hash  # Sort the keys of the current hash
    };
}

1;