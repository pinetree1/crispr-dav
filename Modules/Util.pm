# Miscellaneous utility functions
package Util;
use strict;
use Carp qw(carp croak);
use Excel::Writer::XLSX;

# Generate Excel file from tsv file. 
sub tab2xlsx {
	my ($tabfile, $outfile)=@_;
	croak "Must have tabfile and outfile.\n" if (!$tabfile or !$outfile);	 
	open(my $in, $tabfile) or croak "Cannot open $tabfile\n";
	my $workbook = Excel::Writer::XLSX->new($outfile);
	my $worksheet= $workbook->add_worksheet();
	my $row=0;
	my $col=0;
	while (my $line=<$in>) {
		chomp $line;
		foreach my $e ( split(/\t/, $line) ) {
			$worksheet->write($row, $col++, $e);
		}
		$row++;
		$col=0;
	}
	close $in;
}

## Concontenate tab-delimited files with header
### hasHeader: 0 if the tab file has no header row, 1-has header row.
### infile_aref is a array ref of infiles
sub tabcat {
	my ($infile_aref, $outfile, $hasHeader) = @_;
	croak "Must have outfile and infile_aref.\n" if ( !$outfile or !$infile_aref );	 
	my @infiles = @{$infile_aref};
	my $cmd;
	if ( !$hasHeader ) {
		qx(cat @infiles > $outfile);
	} else {
		my $file = shift @infiles;
		qx(cat $file > $outfile);
		foreach $file ( @infiles ) {
			qx(tail -n +2 $file >> $outfile);
		}
	}
}

1;
