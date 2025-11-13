#!/usr/bin/perl

package config;

use strict;
use warnings;
use v5.14;
use JSON;
use DBI;
use Hash::Merge;
use Exporter; # Gain export capabilities 

our $config_file = "pubpeer_analysis.conf";
our %config      = load_config();

# Exported variables & functions.
our (@EXPORT, @ISA);    # Global variables 

@ISA    = qw(Exporter); # Take advantage of Exporter's capabilities
@EXPORT = qw(
    $config_file
    %config
);                      # Exported variables.

sub load_config {
    unless (-f $config_file) {
        $config_file = "../../pubpeer_analysis.conf";
        die unless -f $config_file;
    }
    my $config = do("./$config_file");
    return %$config;
}

1;