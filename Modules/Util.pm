package Util;

=head1 DESCRIPTION
	
	This package includes various utility subroutines.

=head1 SYNOPSIS

=head1 AUTHOR

Xuning Wang

=cut

use strict;
use Carp qw(croak);
use Excel::Writer::XLSX;

=head2 tab2xlsx

 Usage   : Util::tab2xlsx($tabfile, $outfile)
 Function: Generate Excel file from tab-separated file. 
 Returns : An excel file
 Args    : infile, outfile

=cut

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


=head2 tabcat

 Usage   : Util::tabcat(args)
 Function: Concontenate tab-delimited files with header 
 Returns : 
 Args    : infile_aref, outfile, hasHeader 
	infile_aref is a array ref of infiles
	hasHeader: 0 if the tab file has no header row, 1-has header row.

=cut

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

=head2 run 

 Usage   : Util::run($cmd, $fail_msg, $verbose)
 Function: run a command 
 Returns :
 Args    : cmd, fail_msg, verbose

=cut

sub run {
	my ($cmd, $fail_msg, $verbose, $fail_flag_file) = @_;
	print STDERR "$cmd\n" if $verbose;
	if ( system($cmd) ){
		if ( $fail_flag_file ) {
			qx(touch $fail_flag_file);
		}
		croak "$fail_msg\n";
	}
} 

=head2 getJobName 

 Usage   : Util::getJobName($samplename, $prefix, $suffix)
 Function: Construct a SGE job name based on sample name, prefix and suffix 
 Returns : a job name
 Args    : sample name, prefix and suffix 

=cut

sub getJobName {
	my ($samplename, $prefix, $suffix)=@_;
	croak "Sample name must have at least 2 characters.\n" if length($samplename) < 2;
	croak "No prefix or suffix\n" if !$prefix or !$suffix;

	my $time=`date +%M`; chomp $time;	
	my $jobname = join("", $prefix, $time, substr($samplename, 0, 2), $suffix);
	return $jobname;
}

=head2 getJobStatus 

 Usage   : Util::getJobStatus($tabfile, $outfile)
 Function: Determine whether jobs submitted to SGE queue are completed, running, or failed 
 Returns : an array: job status, running count, waiting count, failed count
 Args    : a hash reference of jobname 

=cut

sub getJobStatus {
	my $jobs = shift;
	my $result = `qstat`;
	my @lines = split(/\n/, $result);
	my $running = 0;
	my $waiting = 0;
	my $failed = 0;

	my $status = 0; # 0-completed, 1-running, 2-failed
	return $status if !@lines;

	shift @lines; 
	shift @lines;
	foreach my $line ( @lines ) {
		next if !$line;
		$line =~ s/^\s+//g;
		my ($jobid, $prior, $name, $user, $state) = split(/\s+/, $line);
		next if !$jobs->{$name};  
		if ($state eq 'r') {
			$running++;
		} elsif ( $state eq 'qw' or $state eq 't') {
			$waiting++;
		} else {
			$failed++;
		}
	}	

	if ( $failed ) {
		$status = 2;
	} elsif ( $waiting or $running ) {
		$status = 1;
	}

	return ($status, $running, $waiting, $failed);
}

=head2 waitForJobs 

 Usage   : Util::waitForJobs($jobs, $interval, $max_time)
 Function: Wait for jobs to complete, or exit when a job failed. 
 Returns :
 Args    : jobs, interval, max_time 
	jobs is hash reference of job names
	interval: number of seconds the program wait before check status
	max_time: number of max seconds the program will wait for the jobs before continuing to next step. 

=cut

sub waitForJobs {
	my ($jobs, $interval, $max_time) = @_;	
	$interval //= 120; # seconds
	$max_time //= 5*24*60*60;  # 5 days

	my $elapsed_time = 10;
	sleep $elapsed_time;

	while ( $elapsed_time < $max_time ) {	
		my @status = getJobStatus($jobs);
		if ( $status[0] == 0 ) {
			return;
		} elsif ( $status[0] == 0 ) {
			croak "Some jobs had failure status on queue.";
		}
		sleep $interval;
		$elapsed_time += $interval;
	}
} 

1;
