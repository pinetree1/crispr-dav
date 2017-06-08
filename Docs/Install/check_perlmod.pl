#!/usr/bin/env perl
# chech required perl modules
use strict;
my @mods = qw(
	Config::Tiny 
	Excel::Writer::XLSX 
	Bio::PrimarySeq 
	Spreadsheet::XLSX 
	Spreadsheet::ParseExcel 
	Time::HiRes 
	JSON 
	CGI 
	URI::Escape
);

foreach my $mod ( @mods ) {
	unless (eval "require $mod") {
		warn "couldn't load $mod: $@";
	}
}

