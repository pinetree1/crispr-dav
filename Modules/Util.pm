package Util;

=head1 DESCRIPTION
	
	This package includes various utility subroutines.

=head1 SYNOPSIS

=head1 AUTHOR

Xuning Wang

=cut

use strict;
use Carp qw(carp croak);
use Excel::Writer::XLSX;

=head2 tab2xlsx

 Usage   : Util::tab2xlsx($tabfile, $outfile)
 Function: Generate Excel file from tab-separated file. 
 Returns : An excel file
 Args    : infile, outfile

=cut

sub tab2xlsx {
    my ( $tabfile, $outfile ) = @_;
    croak "Must have tabfile and outfile.\n" if ( !$tabfile or !$outfile );
    open( my $in, $tabfile ) or croak "Cannot open $tabfile\n";
    my $workbook  = Excel::Writer::XLSX->new($outfile);
    my $worksheet = $workbook->add_worksheet();
    my $row       = 0;
    my $col       = 0;
    while ( my $line = <$in> ) {
        chomp $line;
        foreach my $e ( split( /\t/, $line ) ) {
            $worksheet->write( $row, $col++, $e );
        }
        $row++;
        $col = 0;
    }
    close $in;
}

=head2 tabcat

 Usage   : Util::tabcat(args)
 Function: Concontenate tab-delimited files with header 
 Returns : 
 Args    : infile_aref, outfile, hasHeader 
	infile_aref is a array ref of infiles
	hasHeader: 0 if the tab file has no header row, 1-has header row.

=cut

sub tabcat {
    my ( $infile_aref, $outfile, $hasHeader ) = @_;
    croak "Must have outfile and infile_aref.\n"
      if ( !$outfile or !$infile_aref );
    my @infiles = @{$infile_aref};
    my $cmd;
    if ( !$hasHeader ) {
        qx(cat @infiles > $outfile);
    }
    else {
        my $file = shift @infiles;
        qx(cat $file > $outfile) if -f $file;
        foreach $file (@infiles) {
            qx(tail -n +2 $file >> $outfile) if $file;
        }
    }
}

=head2 run 

 Usage   : Util::run($cmd, $fail_msg, $verbose, fail_flag_file, warn_on_error)
 Function: run a command 
 Returns : command status
 Args    : cmd, fail_msg, verbose, die_on_error, fail_flag_file 
           warn_on_error: 1-warn, 0-die.
           fail_flag_file: if provided, the file will be created.
			
=cut

sub run {
    my ( $cmd, $fail_msg, $verbose, $fail_flag_file, $warn_on_error ) = @_;
    print STDERR "$cmd\n" if $verbose;
    if ( system($cmd) ) {
        if ($fail_flag_file) {
            qx(touch $fail_flag_file);
        }

        if ($warn_on_error) {
            warn "$fail_msg\n";
        }
        else {
            die "$fail_msg\n";
        }
    }
}

=head2 getJobName 

 Usage   : Util::getJobName($prefix, $suffix)
 Function: Construct a SGE job name based on prefix and suffix 
 Returns : a job name
 Args    : prefix and suffix 

=cut

sub getJobName {
    my ( $prefix, $suffix ) = @_;
    croak "No prefix or suffix\n" if !$prefix or !$suffix;

    my $time = `date +%M`;
    chomp $time;
    my $jobname = join( "", $prefix, $time, ".", $suffix );
    return $jobname;
}

=head2 getJobCount 

 Usage   : Util::getJobCount($jobname_href)
 Function: Obtain the number of jobs still on SGE queue  
 Returns : a number
 Args    : a hash reference of jobname 

=cut

sub getJobCount {
    my $jobs   = shift;
    my $result = `qstat`;
    my @lines  = split( /\n/, $result );
    return 0 if !@lines;

    my $n = 0;
    shift @lines;    # remove header line
    shift @lines;    # remove ------ line
    foreach my $line (@lines) {
        next if !$line;
        $line =~ s/^\s+//g;
        my ( $jobid, $prior, $name, $user, $state ) = split( /\s+/, $line );
        next if !$jobs->{$name};
        $n++;
    }

    return $n;
}

=head2 refGeneCoord

 Usage   : Util::refGeneCoord(refGeneFile, refGeneID)
 Function: Return coordinates from UCSC refGene table for a given refseq ID
           refseq ID examples: NM_001005738. It's the 2nd column in the file.
 Returns : an array: (name, chr, strand,  txStart, txEnd, cdsStart, cdsEnd, 
           exonStarts, exonEnds)
 Args    : refGene file, refGene ID

=cut

sub refGeneCoord {
    my ( $refGene_file, $refseq_id ) = @_;
    open(my $inf, $refGene_file) or croak "Could not open $refGene_file\n!";
	while (my $line=<$inf>) {
        chomp $line;
        my @a = split( /\t/, $line);
        if ( uc($a[1]) eq uc($refseq_id) ) {
            return ($a[1], $a[2],$a[3],$a[4],$a[5],$a[6],$a[7],$a[9],$a[10]);
        }
    }
    close $inf;
    return ();
}

1;
