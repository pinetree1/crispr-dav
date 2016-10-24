package NGS; 

=head1 DESCRIPTION

The package is used to perform various NGS tasks, such as filtering, aligning, read counting, variant stats.

=head1 SYNOPSIS

=head1 AUTHOR

Xuning Wang <xuning.wang@bms.com>

=cut
 
use strict;
use File::Basename;
use File::Path qw(make_path);
use Carp qw(croak);
use Data::Dumper;

=head2 new

 Usage   : $obj = new NGS()
 Function: Create a NGS object
 Returns : Returns a NGS object
 Args    : java, samtools, bedtools, bwa, verbose, tmpdir. 
		bedtools must be at least version 2
=cut

sub new {
	my $self = shift;
	my %h = (
		java=>'java',
		samtools=>'samtools',
		bedtools=>'bedtools',
		bwa=>'bwa',
		verbose=>0,
		tmpdir=>'/tmp',
		@_, 
	);	
	bless \%h, $self;
}

=head2 filter_reads

 Usage   : $obj->filter_reads(read1_inf=>'dir1/S1.fastq.gz', read1_outf='dir2/S1.fastq.gz')
 Function: filter reads in .gz fastq file with PRINSEQ prinseq-lite.pl
 Returns : 
 Args    : Required: read1_inf (input read1 file), read1_outf (output read1 file). More optional args.   

=cut

sub filter_reads {
	my $self = shift;
	my %h = (
		prinseq=>'prinseq-lite.pl',
		min_qual_mean=>30,
		min_len=>50,
		ns_max_p=>3,
		read2_inf=>'', 
		read2_outf=>'',	
		@_, 
	);

	required_args(\%h, 'read1_inf', 'read1_outf');
	
	my $f1 = $h{read1_inf};
	my $f2 = $h{read2_inf};
	if ( $f1 !~/\.gz$/ or ( $f2 && $f2 !~/\.gz$/ ) ) {
		croak "Fastq file must be gzipped and has .gz extension";
	} 

	my $param="-min_len $h{min_len}" if defined $h{min_len};
	$param .=" -min_qual_mean $h{min_qual_mean}" if defined $h{min_qual_mean};
	$param .=" -ns_max_p $h{ns_max_p}" if defined $h{ns_max_p};

	my $read1_outf = $h{read1_outf};
	my $read2_outf = $h{read2_outf};

	my ($cmd, $status);	
	my $log="$read1_outf.filter.log";
	if ( !$f2 ) {
		$cmd= "(gunzip -c $f1 | $h{prinseq} -fastq stdin";
		$cmd .= " -out_good $read1_outf -out_bad null $param) &>$log";
		$cmd .= " && gzip -c $read1_outf.fastq > $read1_outf && rm $read1_outf.fastq";
		print STDERR "Filtering fastq: $cmd\n";
		croak "Error: Failed to filter $f1" if system($cmd);
	} else {
		$cmd = "gunzip -c $f1 > $read1_outf && gunzip -c $f2 > $read2_outf";
		$cmd .=" && ($h{prinseq} -fastq $read1_outf -fastq2 $read2_outf";
		$cmd .=" -out_good $read1_outf -out_bad null $param) &>$log";
		$cmd .=" && gzip -c ${read1_outf}_1.fastq > $read1_outf";
		$cmd .=" && gzip -c ${read1_outf}_2.fastq > $read2_outf";
		$cmd .=" && rm -f ${read1_outf}_[12]*.fastq";
		print STDERR "Filtering fastq: $cmd\n" if $self->{verbose};
		croak "Error: Failed to filter $f1 and $f2" if system($cmd);
	}
}

=head2 trim_reads

 Usage   : $obj->trim_reads(read1_inf=>'x', read1_outf=>'y')
 Function: Trim reads with sickle. 
 Returns :
 Args    :	read1_inf, read1_outf

=cut

sub trim_reads {
	my $self = shift;
	my %h = (
		read2_inf =>'', # read2 input file
		read2_outf=>'', # read2 outfile
		singles_outf=>'',  # singles outfile
		trim_logf=>'', 
		scheme=>'sanger',  # quality score scheme
		sickle=>'sickle',
		min_qual_mean=>30,
		min_len=>50,
		@_,   # read1_inf, read1_outf 
	);
		
	required_args(\%h, 'read1_inf', 'read1_outf');
		
	my $endtype= $h{read2_inf}? "pe" : "se";
	if ( $endtype eq "pe" ) {
		required_args(\%h, 'read2_outf' )
	}

	my $cmd = "$h{sickle} $endtype -t $h{scheme} -f $h{read1_inf} -g -o $h{read1_outf}";
	if ( $endtype eq "pe" ) {
		$h{singles_outf} //= "$h{read1_outf}.singles.fastq.gz";

		$cmd .= " -r $h{read2_inf} -p $h{read2_outf} -s $h{singles_outf}";
	}

	$cmd .= " -q $h{min_qual_mean} -l $h{min_len}";
	$cmd .= " > $h{trim_logf}" if $h{trim_logf};
	$cmd .= " && rm -f $h{singles_outf}" if $h{singles_outf};
	print STDERR "$cmd\n" if $self->{verbose};
	return system($cmd);
}

=head2 create_bam

 Usage   : $obj->create_bam(sample=>, read1_inf=>, idxbase=>, bam_outf=> )
 Function: a wrapper function to create bam file, etc from fastq file.
 Returns : array of read counts by bamReadCount().
 Args    : sample, read1_inf, idxbase, bam_outf, and many optional/default args 

=cut

sub create_bam {
	my $self = shift;
	my %h = ( 
		read2_inf=>'', # read2 input file
		picard=>'', # picard path, required if mark_duplicate=1
		mark_duplicate=>0,	# whether to mark duplicate reads

		abra=>'',  # ABRA jar file, required if realign_indel=1	
		target_bed=>'', # e.g. amplicon bed file, required for indel realignment
		realign=>0,	# whether to do realignment
		ref_fasta=>'',  # reference fasta file

		remove_duplicate=>0,	# whether to remove duplicate reads
		chromCount_outfile=>'', # output read counts on chromosomes if file name is provided
		@_
	);	

	required_args(\%h, 'sample', 'read1_inf', 'idxbase', 'bam_outf');

	# bam_outf is final bam file

	$self->bwa_align(read1_inf=>$h{read1_inf},
    	read2_inf=>$h{read2_inf}, id=>$h{sample}, sm=>$h{sample},
    	idxbase=>$h{idxbase},
    	bam_outf=>$h{bam_outf});


	## Indel realignment 
	if ( $h{realign_indel} && $h{abra} && $h{target_bed} && $h{ref_fasta} ) {
		$self->ABRA_realign(bam_inf=>$h{bam_outf}, abra=>$h{abra},
        	target_bed=>$h{target_bed}, ref_fasta=>$h{ref_fasta});
	}

	## Mark duplicates
	if ( $h{mark_duplicate} or $h{remove_duplicate} ) {
		$self->mark_duplicate(bam_inf=>$h{bam_outf}, picard=>$h{picard});
	}

	my @bam_stats = $self->bamReadCount($h{bam_outf});	

	if ( $h{chromCount_outfile} ) {
		$self->chromCount(sample=>$h{sample}, bam_inf=>$h{bam_outf}, 
			outfile=>$h{chromCount_outfile});
	}

	if ( $h{remove_duplicate} ) {
		$self->remove_duplicate($h{bam_outf});
	}
	$self->index_bam($h{bam_outf});

	return @bam_stats;
}

=head2 bwa_align

 Usage   : $obj->bwa_align(read1_inf=>, idxbase=>, bam_outf=>)
 Function: bwa alignment with bwa mem, and sort/index; removing non-primary and supplemental alignment entries
 Returns :
 Args    : read1_inf, idxbase, bam_outf, etc

=cut

sub bwa_align {
	my $self = shift;
	my %h = ( 
		read2_inf=>"", # read2 input file
		param=>"-t 4 -M",
		id=>'', # read group ID
		sm=>'', # read group sample name
		pl=>'ILLUMINA', # read group platform
		@_
	);	

	required_args(\%h, 'read1_inf', 'idxbase', 'bam_outf');
	my $samtools = $self->{samtools};
	my $cmd = "$self->{bwa} mem $h{idxbase} $h{read1_inf}";

	if ($h{read2_inf}) {
		$cmd .= " $h{read2_inf}";
	}

	if ( $h{param} ) {
		$cmd .= " $h{param}";
	}

	if ($h{id} && $h{sm}) {
		$cmd .= " -R \'\@RG\tID:$h{id}\tSM:$h{sm}\tPL:$h{pl}\'";
	}

	$cmd .= " |$samtools view -S -b -F 256 -";
	$cmd .= " |$samtools view -b -F 2048 -"; 
	$cmd .= " |$samtools sort -f - $h{bam_outf} && $samtools index $h{bam_outf}";
	$cmd = "($cmd) &> $h{bam_outf}.bwa.log";
	print STDERR "$cmd\n" if $self->{verbose};
	return system($cmd);	
}

=head2 sort_index_bam

 Usage   : sort_index_bam(bam_inf=>'x.bam')
 Function: sort reads in bam. If bam_outf is not specified, the input bam is replaced.
 Returns :
 Args    : Required arguments: bam_inf; Optional: bam_outf

=cut

sub sort_index_bam {
	my $self = shift;
	my %h = ( @_ );
	required_args(\%h, 'bam_inf');
	my $samtools = $self->{samtools};
	my $cmd;
	if ( $h{bam_outf} ) {
		$cmd = "$samtools sort -f $h{bam_inf} $h{bam_outf}";
		$cmd .= " && $samtools index $h{bam_outf}"; 
	} else {
		$cmd = "mv $h{bam_inf} $h{bam_inf}.tmp";
		$cmd .= " && $samtools sort -f $h{bam_inf}.tmp $h{bam_inf}";
		$cmd .= " && $samtools index $h{bam_inf}";
		$cmd .= " && rm $h{bam_inf}.tmp";
	}

	print STDERR "$cmd\n" if $self->{verbose};
	return system($cmd);
}

=head2 index_bam

 Function: Create index for bam. 
	The resulting index file is <bamfile>.bai. If bam file is x.bam, then index is x.bam.bai
 Args    : bam_inf
 
=cut

sub index_bam {
	my ($self, $bamfile) = @_;
	my $cmd = "$self->{samtools} index $bamfile";
	return system($cmd);
}

=head2 mark_duplicate

 Usage   : $obj->mark_duplicate(bam_inf=>, picard=>'path_to_MarkDuplicates.jar')
 Function: mark but not remove duplicate reads in bam using Picard
 Args    : bam_inf. Optional arguments: bam_outf, picard
	Choose the version of Picard that has MarkDuplicates.jar 

=cut

sub mark_duplicate {
	my $self = shift;
	my %h = (
		metrics=>'.md.metrics',
		bam_outf=>'',
		@_, 
	);

	required_args(\%h, 'bam_inf', 'picard');

	my $prog = $h{picard} . "/MarkDuplicates.jar";
	croak "Cannot find $prog" if !-f $prog;
	
	my $cmd;
	if ( $h{bam_outf} ) {
		$cmd = "$self->{java} -jar $prog I=$h{bam_inf} O=$h{bam_outf} METRICS_FILE=$h{bam_outf}" . $h{metrics};
	} else {
		$cmd = "mv $h{bam_inf} $h{bam_inf}.tmp";
		$cmd .= " && $self->{java} -jar $prog I=$h{bam_inf}.tmp O=$h{bam_inf} METRICS_FILE=$h{bam_inf}" . $h{metrics};
	}

	$cmd .= " REMOVE_DUPLICATES=false ASSUME_SORTED=true";
	$cmd .= " VALIDATION_STRINGENCY=LENIENT CREATE_INDEX=false";
	$cmd .= " MAX_FILE_HANDLES_FOR_READ_ENDS_MAP=1000";
	$cmd .= " TMP_DIR=$self->{tmpdir}";

	if ( $h{bam_outf} ) {
		$cmd .= " && $self->{samtools} index $h{bam_outf}";
	} else {
		$cmd .= " && rm $h{bam_inf}.tmp";
		$cmd .= " && $self->{samtools} index $h{bam_inf}";
	}

	$cmd = "($cmd) &> $h{bam_inf}.md.log";
	print STDERR "$cmd\n" if $self->{verbose};
	return system($cmd);	
}

=head2 ABRA_realign

 Usage   : $obj->ABRA_realign(bam_inf=>, abra=>'path/of/abra.jar', ...) 
 Function: Update bam file with ABRA for enhanced indel detection
 Args    : bam_inf, abra, target_bed, ref_fasta, 
	target_bed is a bed file that specifies the region to realign
	ref_fasta is a reference fasta file.

=cut

sub ABRA_realign {
	my $self = shift;
	my %h = ( 
		bam_outf=>'',
		@_	
	);

	required_args(\%h, 'bam_inf', 'abra', 'target_bed', 'ref_fasta');
	croak "Cannot find ABRA jar file" if !-f $h{abra};
	
	my $tmpdir = $self->{tmpdir}; 

	my $workdir = "$tmpdir/" . basename($h{bam_inf});
	
	my $replace_flag = 0;
	if ( !$h{bam_outf} ) {
		$replace_flag = 1;
		$h{bam_outf} = "$h{bam_inf}.tmp.bam";
	}

	# ABRA requires that tmpdir does not exist and input bam file is already indexed.
	my $cmd = "rm -rf $workdir && mkdir -p $workdir"; 
	$cmd .= " && $self->{java} -Djava.io.tmpdir=$tmpdir -jar $h{abra} --threads 2";
	$cmd .= " --ref $h{ref_fasta} --targets $h{target_bed} --working $workdir";
	$cmd .= " --in $h{bam_inf} --out $h{bam_outf}";
	$cmd .= " && rm -r $workdir";

	if ( $replace_flag) {
		$cmd .= " && mv $h{bam_outf} $h{bam_inf}";
	}
	
	$cmd = "($cmd) &> $h{bam_inf}.abra.log";
	print STDERR "$cmd\n" if $self->{verbose};

	system($cmd);
	if ( $replace_flag ) {
		return $self->sort_index_bam(bam_inf=>$h{bam_inf});
	} else {
		return $self->sort_index_bam(bam_inf=>$h{bam_outf});
	}
}

=head2 remove_duplicate

 Usage   : $obj->remove_duplicate($inbam, $outbam)
 Function: removing duplicates from input bam file that is already marked for duplicates.
 Args    : input bam file, optional output bam file

=cut

sub remove_duplicate {
	my ($self, $inbam, $outbam) = @_;
	croak "Cannot find inbam $inbam.\n" if !-f $inbam;

	my $replace = 0;
	if (!$outbam) {
		$outbam = "$inbam.tmp";
		$replace = 1;
	}

	my $status = system("$self->{samtools} view -b -F 1024 $inbam > $outbam");
	if ( $status == 0 && $replace== 1 ) {
		rename($outbam, $inbam);
	}
}

=head2 fastqReadCount

 Usage   : $obj->fastqReadCount($fastq_file, $gz)
 Function: Count reads in fastq file. If it's gzipped, set gz=1
 Returns : number of reads
 Args    : fastq file, gz flag (1/0)

=cut
	
sub fastqReadCount {
	my ($self, $fastq_file, $gz) = @_;
	my $cmd = $gz? "gunzip -c $fastq_file|wc -l" : "wc -l $fastq_file";
	my $result = qx($cmd);
	chomp $result;
	return $result/4;
}


=head2 bamReadCount

 Usage   : $obj->bamReadCount($bamfile)
 Function: Obtain read counts from bam file. The bam file should be marked duplicates.
 Returns : an array of counts
 Args    : input bam file

=cut

sub bamReadCount {
	my ($self, $bamfile) = @_;
	my $cmd = $self->{samtools} . " view -c $bamfile";
		
	my $bam_reads = qx($cmd 2>/dev/null);
	my $mapped_reads = qx($cmd -F 4 2>/dev/null);
	my $duplicate_reads = qx($cmd -f 1024 2>/dev/null);
	chomp $bam_reads;
	chomp $mapped_reads;
	chomp $duplicate_reads;
	my $uniq_reads = $mapped_reads - $duplicate_reads;

	return ($bam_reads, $mapped_reads, $duplicate_reads, $uniq_reads);
}

=head2 regionReadCount

 Usage   : $obj->regionReadCount(args) 
 Function: Count the number of reads overlapping a region
 Returns : read count
 Args    : bam_inf, chr, start, end. Start and end are 1-based and inclusive.
	In order to count reads in a region (chr, start, end), the bam file must be indexed.  
	The start and end are 1-based chromosome position.

=cut

sub regionReadCount {
	my $self = shift;
	my %h = (min_overlap=>1, @_);
	required_args(\%h, 'bam_inf', 'chr', 'start', 'end');
 
	my $cnt = 0;
	if ( $h{min_overlap}==1 ) {
		$cnt = qx($self->{samtools} view -c $h{bam_inf} $h{chr}:$h{start}-$h{end} 2>/dev/null);
	} else {
		my $ratio = $h{min_overlap}/($h{end} - $h{start} + 1);
		my $bedfile="$h{bam_inf}.tmp.region.bed";
		$self->makeBed($h{chr}, $h{start}, $h{end}, $bedfile);
		my $cmd = "$self->{bedtools} intersect -a $h{bam_inf} -b $bedfile -F $ratio -u";
		$cmd .= " | $self->{samtools} view -c - "; 
		$cnt = qx($cmd);
		unlink $bedfile;
	}
	chomp $cnt;
	return $cnt;
}

=head2 makeBed

 Usage   : $obj->makeBed(chr=>, start=>, end=>, outfile=>)
 Function: create a bed file, with 0-based coordinates: [start coord, end coord).
 Args    : chr, start, end, outfile. start and end is 1-based, by default.

=cut

sub makeBed {
	my $self = shift;
	my %h= (zero_based=>1, @_);
	required_args(\%h, 'chr', 'start', 'end', 'outfile');

	open(my $outf, ">$h{outfile}") or croak $!;	
	my $newstart = $h{zero_based}? $h{start}-1 : $h{start};
	print $outf join("\t", $h{chr}, $newstart, $h{end})."\n";
	close $outf;
}

=head2 readFlow
 
 Usage   : $obj->readFlow(r1_fastq_inf=>, outfile=>, ...)
 Function: Count reads in different stages
 Args    : r1_fastq_inf, bamstat_aref, sample, outfile, etc
	start and end are 1-based.

=cut 

sub readFlow {
	my $self = shift;
	my %h = ( gz=>1, r2_fastq_inf=>'',
		# Below are required for region read count	 
		chr=>'', start=>0, end=>0, bam_inf=>'',  
		min_overlap=>1, 
		@_);

	required_args(\%h, 'r1_fastq_inf',  'bamstat_aref', 'sample', 'outfile');

	open(my $cntf, ">$h{outfile}") or croak $!;
	print $cntf join("\t", "Sample", "RawReads", "QualityReads", "MappedReads", 
			"PctMap", "Duplicates", "PctDup", "UniqueReads", "RegionReads") . "\n";

	my $raw_reads = $self->fastqReadCount($h{r1_fastq_inf}, $h{gz});
	if ( $h{r2_fastq_inf} ) {
		$raw_reads +=  $self->fastqReadCount($h{r2_fastq_inf}, $h{gz});
	}

	my ($bam_reads, $mapped_reads, $duplicate_reads, $uniq_reads)= @{$h{bamstat_aref}};
	my $pct_map = $bam_reads > 0 ? sprintf("%.2f", 100*$mapped_reads/$bam_reads) : "NA";
	my $pct_dup = $bam_reads > 0 ? sprintf("%.2f", 100*$duplicate_reads/$bam_reads) : "NA";

	my $region_reads = "NA";
	if ( $h{chr} && $h{start} && $h{end} && $h{bam_inf} ) {
		$region_reads =	$self->regionReadCount(bam_inf=>$h{bam_inf}, 
			chr=>$h{chr}, start=>$h{start}, end=>$h{end}, 
			min_overlap=>$h{min_overlap});
	}

	print $cntf join("\t", $h{sample}, $raw_reads, $bam_reads, $mapped_reads,
        	$pct_map, $duplicate_reads, $pct_dup, $uniq_reads, $region_reads) . "\n";
	close $cntf;
}

=head2 chromCount

 Usage   : $obj->chromCount(sample='x', bam_inf=>, outfile=> )
 Function: Calculate the number of reads aligned on different chromosomes
 Args    : sample, bam_inf, outfile

=cut
 
sub chromCount {
	my $self = shift;
	my %h = (@_);
	required_args(\%h,, 'sample', 'bam_inf', 'outfile');

	my $result = qx($self->{samtools} view $h{bam_inf} | cut -f 3 | sort | uniq -c);
	open(my $outf, ">$h{outfile}") or croak $!;
	print $outf join("\t", "Sample", "Chromosome", "ReadCount") . "\n";
	foreach my $line ( split(/\n/, $result) ) {
		next if $line !~ /\w/;
		chomp $line;
		my ($reads, $chr)=($line=~/(\d+)\s(\S+)/);
		next if $chr eq '*';
		print $outf join("\t", $h{sample}, $chr, $reads) . "\n"; 
	}
	close $outf;
}

=head2 variantStat

 Usage   : $obj->variantStat(bam_inf=>, outfile=>, )
 Function: Caluculate depth, indel, SNPs in a bam file.
 Args    : bam_inf, ref_fasta, outfile, etc.
	pysamstats must be in PATH or specified. Require python module pysam.

=cut

sub variantStat {
	my $self = shift;
	my %h = (
		max_depth=>1000000,
		window_size=>1,
		type=>'variation',
		chr=>'',
		start=>0,
		end=>0,
		pysamstats=>'pysamstats',
		@_,	
	);	

	required_args(\%h, 'bam_inf', 'ref_fasta', 'outfile'); 
	my $cmd = "$h{pysamstats} --type $h{type} --max-depth $h{max_depth}";
	$cmd .= " --window-size $h{window_size} --fasta $h{ref_fasta}";
	$cmd .= " --fields chrom,pos,ref,reads_all,matches,mismatches,deletions,insertions,A,C,T,G,N";
	if ( $h{chr} && $h{start} > 0 && $h{end} > 0 ) {
		$cmd .= " --chromosome $h{chr} --start $h{start} --end $h{end}";	
	}
	$cmd .= " $h{bam_inf} --output $h{outfile}";
	
	print STDERR "$cmd\n" if $self->{verbose};
	
	return system($cmd);		
}

=head2 required_args
 
 Usage   : $obj->required_args($href)
 Function: Quit if a required argument is missing.
 Args    : a hash reference

=cut

sub required_args {
	my $href = shift;
	foreach my $arg ( @_ ) {
		if (!defined $href->{$arg}) {
			croak "Missing required argument: $arg";
		} 
	}
}

=head2 targetSeq

 Usage   : $obj->targetSeq(args)
 Function: Find reads that overlap with the target region. 
 Args    : bam_inf, chr, target_start, target_end, 
			outfile_targetSeq, outfile_indelPct, outfile_indelLen
	target_start and target_end are 1-based and inclusive.

=cut

sub targetSeq {
	my $self = shift;
	my %h = (
		min_mapq=>0,
		min_overlap=>1,
		target_name=>'',  # DGKA_CR1
		ref_name=>'', # hg19
		sample=>'',
		@_	
	);

	required_args(\%h, 'bam_inf', 'chr', 'target_start', 'target_end', 
		'outfile_targetSeq', 'outfile_indelPct', 'outfile_indelLen');

	open(my $seqf, ">$h{outfile_targetSeq}") or croak $!;
	open(my $pctf, ">$h{outfile_indelPct}") or croak $!;
	open(my $lenf, ">$h{outfile_indelLen}") or croak $!;

	print $seqf join("\t", "ReadName", "TargetSeq", "IndelStr", "OffsetIndelStr", 
			"Strand", "IndelLength") . "\n";
	print $pctf join("\t", "Sample", "CrisprSite", "Reference", "CrisprRegion", "TargetReads", 
			"WtReads", "IndelReads", "PctWt", "PctIndel", "InframeIndel", "PctInframeIndel") . "\n";
	print $lenf join("\t", "Sample", "CrisprSite", "CrisprRegion", "IndelStr", 
		"ReadCount", "ReadPct", "IndelLength", "FrameShift") . "\n"; 

	my $ratio = $h{min_overlap}/($h{target_end} - $h{target_start} + 1);
	my $bedfile="$h{bam_inf}.tmp.target.bed";
	$self->makeBed(chr=>$h{chr}, start=>$h{target_start}, end=>$h{target_end}, outfile=>$bedfile);
	my $cmd = "$self->{bedtools} intersect -a $h{bam_inf} -b $bedfile -F $ratio -u";
	$cmd .= " | $self->{samtools} view -";
	print STDERR "$cmd\n" if $self->{verbose};

	open(P, "$cmd|") or croak $!;

	# reads overlapping target region that meet min_mapq and min_overlap
	my $overlap_reads = 0; 

	# among total reads, those with at least 1 base of indel inside target region.
	my $indel_reads = 0; 
	my $inframe_indel_reads = 0;
	my %freqs; # frequencies of alleles
	
	while (my $line=<P>) {
		my @info = $self->extractReadRange($line, $h{chr}, $h{target_start}, 
			$h{target_end}, $h{min_mapq});
		next if !@info;

		$overlap_reads ++;

		if ($info[2] =~ /[ID]/) {
			$indel_reads ++;  
			$inframe_indel_reads++ if $info[5] % 3 == 0;
			$freqs{$info[2]}++;
		} else {
			$freqs{WT}++;
		}

		print $seqf join("\t", @info)  . "\n";
	} # end while

	#unlink $bedfile;
	return if !$overlap_reads; 

	## Output read counts

	my $wt_reads = $overlap_reads - $indel_reads;
	my $pct_wt = sprintf("%.2f", $wt_reads * 100/$overlap_reads);
	my $pct_indel = sprintf("%.2f", 100 - $pct_wt);
	my $pct_inframe = sprintf("%.2f", $inframe_indel_reads * 100/$overlap_reads);
	
	print $pctf join("\t", $h{sample}, $h{target_name}, $h{ref_name}, 
		"$h{chr}:$h{target_start}-$h{target_end}", 
		$overlap_reads, $wt_reads, $indel_reads, $pct_wt, $pct_indel,
		$inframe_indel_reads, $pct_inframe) . "\n";

	## Output allele frequencies in descending order
	foreach my $key (sort {$freqs{$b}<=>$freqs{$a}} keys %freqs) {
		my $reads = $freqs{$key};
		my $pct = sprintf("%.2f", $reads * 100 /$overlap_reads);

		my $indel_len = 0;  
		my $frame_shift = "N";
		if ( $key ne "WT" ) {
			$indel_len = _getIndelLength($key);
			$frame_shift = $indel_len%3 ? "Y" : "N";
		} 

		print $lenf join("\t", $h{sample}, $h{target_name}, 
			"$h{chr}:$h{target_start}-$h{target_end}", 
			$key, $reads, $pct, $indel_len, $frame_shift) . "\n";
	}
}

=head2 extractReadRange

 Usage   : $obj->extractReadRange($sam_record, $chr, $start, $end, $min_mapq)
 Function: extract read sequence within a range 
 Args    : $sam_record, $chr, $start, $end, $min_mapq 
	start and end are 1-based and inclusive.

=cut

sub extractReadRange {
	my ($self, $sam_record, $chr, $start, $end, $min_mapq)=@_; 
	my ($qname, $flag, $refchr, $align_start, $mapq, $cigar, 
		$mate_chr, $mate_start, $tlen, $seq, $qual ) = split(/\t/, $sam_record);

	return if ($min_mapq && $mapq < $min_mapq);  

	# 101900216:101900224:D:-:101900224:101900225:I:G
	my $indelstr='';  # position are 1-based. 
	my $indel_length = 0;

	# read sequence comparable to reference but with insertion removed and deletion added back.
	my $newseq;
	my $chr_pos = $align_start -1;  # pos on chromosome
	my $seq_pos = 0; # position on read sequence

	# split cigar string between number and letter
	my @cig = split(/(?<=\d)(?=\D)|(?<=\D)(?=\d)/, $cigar);			

	for (my $i=0; $i< @cig-1; $i +=2 ) {
		my $len = $cig[$i];
		my $letter=$cig[$i+1];
		if ( $letter eq "S" ) {
			$seq_pos += $len;
		} elsif ( $letter eq "M" ) {
			$newseq .= substr($seq, $seq_pos, $len);
			$seq_pos += $len;
			$chr_pos += $len;
		} elsif ( $letter eq "D" ) {
			$newseq .= '-' x $len;
			my $del_start = $chr_pos+1;
			$chr_pos += $len;

			# keep the deletion if it overlaps the target region by 1 base.
			if ( _isOverlap($start, $end, $del_start, $chr_pos, 1)) {
				$indelstr .= "$del_start:$chr_pos:D:-:";
				$indel_length += -$len;
			}
		} elsif ( $letter eq "I" ) {
			my $inserted_seq = substr($seq, $seq_pos, $len);
			$seq_pos += $len;

			# keep the insertion if it overlaps the target region by 1 base. 
			if ( _isOverlap($start, $end, $chr_pos, $chr_pos+1, 1) ) {
				$indelstr .= $chr_pos . ":" . ($chr_pos+1) . ":I:$inserted_seq:";
				$indel_length += $len;
			}			
		} # end if 
	}# end for 

	# sequence in specified range
	my $range_seq = substr($newseq, $start-$align_start, $end-$start+1);


	# 8:16:D:-:16:17:I:G  postions are 1-based.
	my $offset_indelstr;  # indel str with offset locations.
	foreach my $e (split(/:/, $indelstr)){
		$e = $e-$start+1 if $e =~ /^\d+$/; 	
		$offset_indelstr .= $e . ":";
	} 

	$indelstr =~ s/:$//; 
	$offset_indelstr =~ s/:$//;

	my $strand = $flag & 16 ? '-' : '+';
	return ($qname, $range_seq, $indelstr, $offset_indelstr, $strand, $indel_length); 
}

sub _getIndelLength {
	my $indelstr = shift;
	## e.g. 56330828:56330829:D::56330837:56330838:I:CCC
	my @a = split(/:/, $indelstr);
	my $len = 0;
	for (my $i=0; $i<@a; $i +=4) {
		if ( $a[$i+2] eq "D" ) {
			$len -= $a[$i+1] - $a[$i] + 1;
		} elsif ( $a[$i+2] eq "I" ) { 		
			$len += length($a[$i+3]);
		}
	}
	return $len;
}

sub _isOverlap {
	my ($subj_start, $subj_end, $query_start, $query_end, $min_overlap) = @_;
	$min_overlap //= 1;

	my %subj;
	for (my $i=$subj_start; $i<=$subj_end; $i++) {
		$subj{$i}=1;
	}

	my $overlap = 0;
	for (my $i=$query_start; $i<= $query_end; $i++) {
		$overlap ++ if $subj{$i}; 	
	}

	return $overlap >= $min_overlap? 1:0;
}

=head2 categorizeHDR

 Usage   : $obj->categorizeHDR(bam_inf=>, ...)
 Function: To classify oligos in HDR (homology directed repair) region into different categories 
 Args    : bam_inf, chr, base_changes, sample, stat_outf 
	base_changes is a comma-separated strings of positons and bases. Format: <pos><base>,...
	for example, 101900208C,101900229G,101900232C,101900235A. Bases are on positive strand, and 
	are intended new bases, not reference bases. 

=cut

sub categorizeHDR {
	my $self = shift;
	my %h = (
		min_mapq=>0,
		@_	
	);

	required_args(\%h, 'bam_inf', 'chr', 'base_changes', 'sample', 'stat_outf');

	my $sample = $h{sample};
	my $chr = $h{chr};

	# intended base changes	
	my %alt; # pos=>base
	foreach my $mut (split /,/, $h{base_changes}) {
		my ($pos, $base) = ( $mut =~ /(\d+)(\D+)/ );
		$alt{$pos} = uc($base); 
	}

	my $outdir = dirname($h{stat_outf});
	make_path($outdir);

	# create bed file spanning the HDR SNPs. Position format: [Start, end).
	my $bedfile="$outdir/$sample.hdr.bed";
	my @pos = sort {$a <=> $b} keys %alt;
	my $hdr_start = $pos[0];
	my $hdr_end = $pos[-1];
	$self->makeBed(chr=>$h{chr}, start=>$hdr_start, end=>$hdr_end, outfile=>$bedfile);

	# create bam file containing HDR bases.
	my $hdr_bam = "$outdir/$sample.hdr.bam";

	my $samtools = $self->{samtools};
	my $cmd = "$self->{bedtools} intersect -a $h{bam_inf} -b $bedfile -F 1 -u";
	$cmd .= " > $hdr_bam && $samtools index $hdr_bam";
	print STDERR "$cmd\n" if $self->{verbose};
	croak "Failed to create $hdr_bam\n" if system($cmd);

	## create HDR seq file
	my $hdr_seq_file = "$outdir/$sample.hdr.seq";
	$self->extractHDRseq($hdr_bam, $chr, $hdr_start, $hdr_end, $hdr_seq_file, $h{min_mapq});

	## parse HDR seq file to categorize HDR
	my %alts; # key position is offset by $start
	foreach my $coord ( keys %alt ) {
		$alts{$coord - $hdr_start}=$alt{$coord};
	}
		
	my @p = sort {$a <=> $b} keys %alts;
	my $snps = scalar(@p);# number of intended base changes	
	my $total = 0; # total reads
	my $perfect_oligo = 0; # perfect HDR reads.
	my $edit_oligo = 0; # reads with 1 or more desired bases, but also width indels 
	my $partial_oligo = 0; # reads with some but not all desired bases, no indel.
	my $non_oligo = 0; # reads without any desired base changes, regardless of indel 

	open( my $inf, $hdr_seq_file) or croak $!;
	while ( my $line = <$inf> ) {
		next if $line !~ /\w/;
		chomp $line;
		my ($qname, $hdr_seq, $insertion) = split(/\t/, $line);
		my $isEdited = 0;
		if ( $insertion =~ /I/ or $hdr_seq =~ /\-/ ) {
			$isEdited = 1;
		}
		
		my @bases = split(//, $hdr_seq);
		my $alt_cnt = 0; # snp base cnt
		foreach my $i ( @p ) {
			if ( $bases[$i] eq $alts{$i} ) {
				$alt_cnt++;
			}	
		}			

		if ( $alt_cnt == 0 ) {
			$non_oligo ++;
			print STDERR "$line\tNonOligo\n" if $h{verbose};
		} else {
			if ( $isEdited ) {
				$edit_oligo ++;
				print STDERR "$line\tEdit\n" if $h{verbose};
			} else {
				if ( $alt_cnt == $snps ) {
					$perfect_oligo ++;
					print STDERR "$line\tPerfect\n" if $h{verbose};	
				} else {
					$partial_oligo ++;
					print STDERR "$line\tPartial\n" if $h{verbose};
				} 
			}	
		}

		$total ++;

	} # end while

	open(my $outf, ">$h{stat_outf}") or croak $!;
	
	my @cnames = ("PerfectOligo", "EditedOligo", "PartialOligo", "NonOligo");
	my @pct_cnames;
	foreach my $cn (@cnames) {
		push (@pct_cnames, "Pct$cn");
	}

	my @values = ($perfect_oligo, $edit_oligo, $partial_oligo, $non_oligo);
	my @pcts;
	foreach my $v ( @values ) {
		push(@pcts, $total? sprintf("%.2f", $v*100/$total) : 0 );
	}	

	print $outf join("\t", "Sample", "TotalReads", @cnames, @pct_cnames) . "\n";
	print $outf join("\t", $sample, $total, @values, @pcts) . "\n";

	close $outf;
}

=head2 extractHDRseq 

 Usage   : $obj->extractHDRseq(args)
 Function: read the bam entries and categorize the HDRs 
 Returns :
 Args    : hdr_start, hdr_end are 1-based inclusive. They are the first and last position
	of intended base change region of HDR

=cut

# read the bam entries and categorize the HDRs
# start, end are 1-based inclusiv. They are the first and last position 
# of intended base change region of HDR
sub extractHDRseq{
	my ($self, $hdr_bam, $chr, $hdr_start, $hdr_end, $out_hdr_seq, $min_mapq) = @_;

	open(my $seqf, ">$out_hdr_seq") or croak $!;
	open(my $pipe, "$self->{samtools} view $hdr_bam|") or croak $!;
	while (my $line=<$pipe>) {
		my @info = $self->extractReadRange($line, $chr, $hdr_start, $hdr_end, $min_mapq);
		print $seqf join("\t", @info)."\n" if @info;		
	}
	close $pipe;
	close $seqf;
}

=head2 getRecord
 
 Usage   : $obj->getRecord($bedfile, $region_name)
 Function: Get an entry of specific region_name from  a bed file  
 Returns : An array of items in bed entry
 Args    : bed_file, region_name (the 4th field) 

=cut

sub getRecord {
	my ($self, $bedfile, $region_name) = @_;	
	open(my $fh, $bedfile) or croak $!;
	while (<$fh>) {
		chomp;
		my @a = split /\t/;
		if ( !$region_name or $region_name eq $a[3]) {
			return @a;	
		}	
	}
	close $fh;
}

1;
