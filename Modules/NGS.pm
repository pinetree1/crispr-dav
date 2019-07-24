package NGS;

=head1 DESCRIPTION

The package is used to perform various NGS tasks, such as filtering, aligning, read counting, variant stats.

=head1 SYNOPSIS

=head1 AUTHOR

Xuning Wang

=cut

use strict;
use File::Basename;
use File::Path qw(make_path);
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
    my %h    = (
        java     => 'java',
        samtools => 'samtools',
        bedtools => 'bedtools',
        bwa      => 'bwa',
        prinseq  => 'prinseq-lite.pl',
        pysamstats=> 'pysamstats',
        flash    => 'flash',
        verbose  => 0,
        tmpdir   => '/tmp',
        @_,
    );
    bless \%h, $self;
}


=head2 merge_reads

 Usage   : $obj->merge_reads(r1_fastq_inf=>'dir1/S1.fastq.gz', r2_fastq_inf='dir2/S1.fastq.gz', ...)
 Function: merge paired-end reads with flash
 Returns : number indicating success or failure code  
 Args    : Required: r1_fastq_inf, r2_fastq_inf, outdir, prefix. 
           Optional: params: flash parameters in quotes if there is space.   

=cut

sub merge_reads {
    my $self = shift;
    my %h    = (
        params => '',
        @_
    );

    required_args( \%h, 'r1_fastq_inf', 'r2_fastq_inf',
        'outdir', 'prefix'); 

    my $cmd = $self->{flash}." -d $h{outdir} -o $h{prefix} $h{params} -t 1 -z";
    $cmd .= " $h{r1_fastq_inf} $h{r2_fastq_inf} &> $h{outdir}/$h{prefix}.flash.log";
    print STDERR "\nMerging paired-end reads.\n";
    print STDERR "$cmd\n" if $self->{verbose};
    my $status = system($cmd);
    print STDERR "\nFailed in merging paired-end reads.\n" if $status;
    return $status;
}

=head2 filter_reads

 Usage   : $obj->filter_reads(read1_inf=>'dir1/S1.fastq.gz', read1_outf='dir2/S1.fastq.gz')
 Function: filter reads in .gz fastq file with PRINSEQ prinseq-lite.pl
 Returns : number indicating success or failure code  
 Args    : Required: read1_inf (input read1 file), read1_outf (output read1 file). More optional args.   

=cut

sub filter_reads {
    my $self = shift;
    my %h    = (
        min_qual_mean => 30,
        min_len       => 50,
        ns_max_p      => 3,
        read2_inf     => '',
        read2_outf    => '',
        @_,
    );

    required_args( \%h, 'read1_inf', 'read1_outf' );
    my $read1_outf = $h{read1_outf};
    my $read2_outf = $h{read2_outf};

    my $ZERO_INIT_READ = 1;
    my $ZERO_GOOD_READ = 2;
    my $OTHER_FAILURE  = 3;

    my $f1 = $h{read1_inf};
    my $f2 = $h{read2_inf};
    if ( $f1 !~ /\.gz$/ or ( $f2 && $f2 !~ /\.gz$/ ) ) {
        print STDERR "Fastq file must be gzipped and has .gz extension";
        return $OTHER_FAILURE;
    }

    # fastq file cannot be empty
    my $readcount = `gunzip -c $f1 |wc -l`; 
    chomp $readcount;
    if ( $readcount == 0 ) {
        print STDERR "Fastq file $f1 is empty";
        `gzip -c /dev/null > $read1_outf`;
        `gzip -c /dev/null > $read2_outf` if $f2; 
        return $ZERO_INIT_READ;
    }

    my $param = "-min_len $h{min_len}" if defined $h{min_len};
    $param .= " -min_qual_mean $h{min_qual_mean}" if defined $h{min_qual_mean};
    $param .= " -ns_max_p $h{ns_max_p}"           if defined $h{ns_max_p};

    my ( $cmd, $status );

    my $log = "$read1_outf.filter.log";
    my $prinseq = $self->{prinseq};
    if ( !-f $f2 ) {
        print STDERR "\nFiltering single-end fastq.\n";
        $cmd = "(gunzip -c $f1 | $prinseq -fastq stdin" .
            " -out_good $read1_outf -out_bad null $param) &>$log";
        print STDERR "$cmd\n" if $self->{verbose};
        $status = system($cmd);
        if ($status == 0) {
            if ( ! -f "$read1_outf.fastq" ) {
                # zero good reads. All bad reads.
                `gzip -c /dev/null > $read1_outf`;
                $status = $ZERO_GOOD_READ;

            } else { 
                $cmd = "gzip -c $read1_outf.fastq > $read1_outf && rm $read1_outf.fastq";
                print STDERR "$cmd\n" if $self->{verbose};
                $status = system($cmd);
                if ( $status ) {
                    $status = $OTHER_FAILURE;
                }
            }
        } else {
            $status = $OTHER_FAILURE;
        } 
    }
    else {
        print STDERR "\nFiltering paired-end fastqs.\n";
        $cmd = "gunzip -c $f1 > $read1_outf && gunzip -c $f2 > $read2_outf" . 
            " && ($prinseq -fastq $read1_outf -fastq2 $read2_outf" .
            " -out_good $read1_outf -out_bad null $param) &>$log";
        print STDERR "$cmd\n" if $self->{verbose};
        $status = system($cmd);
        if ($status == 0) {
            if ( ! -f "${read1_outf}_1.fastq" or !-f "${read1_outf}_2.fastq" ) {
                `gzip -c /dev/null > $read1_outf`;
                `gzip -c /dev/null > $read2_outf`;
                $status = $ZERO_GOOD_READ;
            } else {
                $cmd = "gzip -c ${read1_outf}_1.fastq > $read1_outf" .
                   " && gzip -c ${read1_outf}_2.fastq > $read2_outf" .
                   " && rm -f ${read1_outf}_[12]*.fastq";
                print STDERR "$cmd\n" if $self->{verbose};
                $status = system($cmd);
                if ( $status ) {
                    $status = $OTHER_FAILURE;
                }
            }
        } else {
            $status = $OTHER_FAILURE;
        }
    }

    return $status;
}

=head2 create_bam

 Usage   : $obj->create_bam(sample=>, read1_inf=>, idxbase=>, bam_outf=> )
 Function: a wrapper function to create bam file, etc from fastq file.
 Returns : array of read counts by bamReadCount(), or array of single element of failure status code.
 Args    : sample, read1_inf, idxbase, bam_outf, and many optional/default args 

=cut

sub create_bam {
    my $self = shift;
    my %h    = (
        read2_inf      => '',    # read2 input file
        picard         => '',    # picard path, required if mark_duplicate=1
        mark_duplicate => 0,     # whether to mark duplicate reads

        abra => '',              # ABRA jar file, required if realign_indel=1
        target_bed =>
          '',    # e.g. amplicon bed file, required for indel realignment
        realign   => 0,     # whether to do realignment
        ref_fasta => '',    # reference fasta file

        remove_duplicate => 0,    # whether to remove duplicate reads
        chromCount_outfile =>
          '',    # output read counts on chromosomes if file name is provided
        @_
    );

    required_args( \%h, 'sample', 'read1_inf', 'idxbase', 'bam_outf' );

    # bam_outf is final bam file

    my $status = $self->bwa_align(
        read1_inf => $h{read1_inf},
        read2_inf => $h{read2_inf},
        id        => $h{sample},
        sm        => $h{sample},
        idxbase   => $h{idxbase},
        bam_outf  => $h{bam_outf}
    );
    return ($status) if $status;

    my $single = 1;
    if ( $h{read2_inf} ) {
        $single = 0;
    }

    ## Indel realignment
    if ( $h{realign} && $h{abra} && $h{target_bed} && $h{ref_fasta} ) {
        $status = $self->ABRA_realign(
            bam_inf    => $h{bam_outf},
            abra       => $h{abra},
            target_bed => $h{target_bed},
            ref_fasta  => $h{ref_fasta},
            single     => $single
        );
        return ($status) if $status;
    }

    my $dupStat = 0;
    ## Mark duplicates
    if ( $h{mark_duplicate} or $h{remove_duplicate} ) {
        $dupStat = 1;
        $status  = $self->mark_duplicate(
            bam_inf => $h{bam_outf},
            picard  => $h{picard}
        );
        return ($status) if $status;
    }

    my @bam_stats = $self->bamReadCount( $h{bam_outf}, $dupStat );

    if ( $h{chromCount_outfile} ) {
        $self->chromCount(
            sample  => $h{sample},
            bam_inf => $h{bam_outf},
            outfile => $h{chromCount_outfile}
        );
    }

    if ( $h{remove_duplicate} ) {
        $status = $self->remove_duplicate( $h{bam_outf} );
        if ( $status == 0 ) {
            $status = $self->index_bam( $h{bam_outf} );
        }
        return ($status) if $status;
    }

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
    my %h    = (
        read2_inf    => "",            # read2 input file
        param        => "-t 4 -M",
        id           => '',            # read group ID
        sm           => '',            # read group sample name
        pl           => 'ILLUMINA',    # read group platform
        @_
    );

    required_args( \%h, 'read1_inf', 'idxbase', 'bam_outf' );
    my $samtools = $self->{samtools};
    my $cmd      = "$self->{bwa} mem";
    $cmd .= " $h{param}" if $h{param};
    if ( $h{id} && $h{sm} ) {
        $cmd .= " -R \'\@RG\tID:$h{id}\tSM:$h{sm}\tPL:$h{pl}\'";
    }
    $cmd .= " $h{idxbase} $h{read1_inf}";
    $cmd .= " $h{read2_inf}" if -f $h{read2_inf};
    $cmd .= " |$samtools view -S -b -F 256 -";
    $cmd .= " |$samtools view -b -F 2048 -";
    $cmd .= " -o $h{bam_outf}";

    $cmd = "($cmd) &> $h{bam_outf}.bwa.log";
    print STDERR "\nAligning with BWA.\n";
    print STDERR "$cmd\n" if $self->{verbose};

    my $status = system($cmd);
    if ( $status == 0 ) {
        $status = $self->clean_header( $h{bam_outf} );
    }

    if ( $status == 0 ) {
        $status = $self->sort_index_bam( bam_inf => $h{bam_outf} );
    }

    return $status;
}

=head2 clean_header

 Usage   : clean_header(bam_inf)
 Function: remove the '-R @RG	ID: ...' from the '@PG	ID:bwa' line as the two IDs clash and caused problem
           for Picard and ABRA
 Returns : command status 
 Args    : input bam file. The resulting bam file is the same.

=cut

sub clean_header {
    my ( $self, $inbam ) = @_;
    my $header   = "$inbam.header";
    my $samtools = $self->{samtools};
    qx($samtools view -H $inbam > $header);
    open( my $inf,  $header );
    open( my $outf, ">$header.new" );
    while ( my $line = <$inf> ) {
        if ( $line =~ /^(\@PG\tID:bwa\tPN:bwa\tVN:\S+)/ ) {
            print $outf "$1\n";
        }
        else {
            print $outf $line;
        }
    }
    close $outf;

    # reheader
    my $cmd = "$samtools reheader $header.new $inbam > $inbam.tmp";
    $cmd .= " && mv $inbam.tmp $inbam";
    $cmd .= " && rm $header && rm $header.new";
    print STDERR "\nCleaning BAM header line.\n";
    my $status = system($cmd);
    print STDERR "Failed in cleaning bam header.\n" if $status;
    return $status;
}

=head2 merge_bam

 Usage   : merge_bam(bam_inf_aref=>, bam_outf=>, sort_index=>1)
 Function: merge bam files with optional sorting and indexing. 
 Returns : command status
 Args    : Required arguments: bam_inf_aref (array reference), bam_outf

=cut

sub merge_bam {
    my $self = shift;
    my %h    = (sort_index=>0, @_);
    required_args (\%h, 'bam_inf_aref', 'bam_outf');
    my $cmd = $self->{samtools} . " merge $h{bam_outf} " . join(" ", @{$h{bam_inf_aref}}); 
    print STDERR "\nMerging bam files.\n";
    print STDERR "$cmd\n" if $self->{verbose};
    my $status = system($cmd);
    if ( $h{sort_index} ) {
        $status = $self->sort_index_bam(bam_inf=>$h{bam_outf});
    }
    return $status;
}

=head2 sort_index_bam

 Usage   : sort_index_bam(bam_inf=>'x.bam')
 Function: sort reads in bam. If bam_outf is not specified, the input bam is replaced.
 Returns : command status
 Args    : Required arguments: bam_inf; Optional: bam_outf

=cut

sub sort_index_bam {
    my $self = shift;
    my %h    = (@_);
    required_args( \%h, 'bam_inf' );

    my $status = $self->sort_bam(%h);
    if ( $status == 0 ) {
        my $outbam = $h{bam_outf} ? $h{bam_outf} : $h{bam_inf};
        $status = $self->index_bam($outbam);
    }

    return $status;
}

=head2 sort_bam

 Usage   : sort_bam(bam_inf=>'x.bam')
 Function: sort reads in bam. If bam_outf is not specified, the input bam is replaced.
 Returns : command status 
 Args    : Required arguments: bam_inf; Optional: bam_outf

=cut

sub sort_bam {
    my $self = shift;
    my %h    = (@_);
    required_args( \%h, 'bam_inf' );
    my $samtools = $self->{samtools};
    my $inbam    = $h{bam_inf};
    my $outbam   = $h{bam_outf} ? $h{bam_outf} : "$inbam.sort.out.bam";

    # Old (e.g. 0.1.19) and new (e.g. 1.3.1) versions of samtools have 
    # different and imcompatible syntax for sorting bam.
    # The -o in old version is a switch for output to stdout: 
    # samtools sort -o inbam fake.outbam > real.outbam
    # The -o in new version accept file argument: 
    # samtools sort -o outbam -O BAM inbam

    print STDERR "\nSorting bam.\n";

    # Old version samtools syntax
    my $cmd1 = "$samtools sort -f $inbam $outbam";

    # New version samtools syntax
    my $cmd2 = "$samtools sort -o $outbam -O BAM $inbam";

    # Try old version first. If it does not work, then try the new version.
    my $status = system("$cmd1 2>/dev/null");
    if ($status) {
        $status = system("$cmd2 2>/dev/null");
    }

    if ($status) {
        print STDERR "Failed in sorting bam.\n";
    }
    else {
        # Replace input bam when bam_outf is not specified
        if ( !$h{bam_outf} ) {
            $status = system("mv $outbam $inbam");
            print STDERR "Failed in renaming bam file after sorting.\n"
              if $status;
        }
    }
    return $status;
}

=head2 index_bam

 Function: Create index for bam. 
	The resulting index file is <bamfile>.bai. If bam file is x.bam, then index is x.bam.bai
 Args    : bam_inf
 
=cut

sub index_bam {
    my ( $self, $bamfile ) = @_;
    my $cmd = "$self->{samtools} index $bamfile";
    print STDERR "\nIndexing bam.\n";
    my $status = system($cmd);
    print STDERR "Failed in indexing bam.\n" if $status;
    return $status;
}

=head2 mark_duplicate

 Usage   : $obj->mark_duplicate(bam_inf=>, picard=>'path_to_MarkDuplicates.jar')
 Function: mark but not remove duplicate reads in bam using Picard
 Args    : bam_inf. Optional arguments: bam_outf, picard
	Choose the version of Picard that has MarkDuplicates.jar 

=cut

sub mark_duplicate {
    my $self = shift;
    my %h    = (
        metrics  => '.md.metrics',
        bam_outf => '',
        @_,
    );

    required_args( \%h, 'bam_inf', 'picard' );

    my $prog = $h{picard} . "/MarkDuplicates.jar";

    my $cmd;
    if ( $h{bam_outf} ) {
        $cmd = "$self->{java} -jar $prog I=$h{bam_inf} O=$h{bam_outf}" . 
            " METRICS_FILE=$h{bam_outf} $h{metrics}";
    }
    else {
        $cmd = "mv $h{bam_inf} $h{bam_inf}.tmp && $self->{java} -jar $prog" .
          " I=$h{bam_inf}.tmp O=$h{bam_inf} METRICS_FILE=$h{bam_inf} $h{metrics}";
    }

    $cmd .= " REMOVE_DUPLICATES=false ASSUME_SORTED=true";
    $cmd .= " VALIDATION_STRINGENCY=LENIENT CREATE_INDEX=false";
    $cmd .= " MAX_FILE_HANDLES_FOR_READ_ENDS_MAP=1000";
    $cmd .= " TMP_DIR=$self->{tmpdir}";

    if ( $h{bam_outf} ) {
        $cmd .= " && $self->{samtools} index $h{bam_outf}";
    }
    else {
        $cmd .= " && rm $h{bam_inf}.tmp";
        $cmd .= " && $self->{samtools} index $h{bam_inf}";
    }

    $cmd = "($cmd) &> $h{bam_inf}.md.log";
    print STDERR "\nMarking duplicates.\n";
    print STDERR "$cmd\n" if $self->{verbose};
    my $status = system($cmd);
    print STDERR "Failed in marking duplicates.\n" if $status;
    return $status;
}

=head2 ABRA_realign

 Usage   : $obj->ABRA_realign(bam_inf=>, abra=>'path/of/abra.jar', ...) 
 Function: Update bam file with ABRA for enhanced indel detection
 Args    : bam_inf, abra, target_bed, ref_fasta, single 
	target_bed is a bed file that specifies the region to realign
	ref_fasta is a reference fasta file.
        single=>0 is for PE reads; single=>1 is for SE read 

=cut

sub ABRA_realign {
    my $self = shift;
    my %h    = (
        bam_outf => '',
        @_
    );

    required_args( \%h, 'bam_inf', 'abra', 'target_bed', 'ref_fasta', 'single' );

    my $tmpdir = $self->{tmpdir};

    my $workdir = "$tmpdir/" . basename( $h{bam_inf} ) . "_dir";

    my $replace_flag = 0;
    if ( !$h{bam_outf} ) {
        $replace_flag = 1;
        $h{bam_outf} = "$h{bam_inf}.realign.bam";
    }

    # ABRA requires that workdir does not exist and input bam 
    # file is already indexed.
    my $cmd = "rm -rf $workdir && mkdir -p $workdir" .
      " && $self->{java} -Djava.io.tmpdir=$tmpdir -jar $h{abra} --threads 2" .
      " --ref $h{ref_fasta} --targets $h{target_bed} --working $workdir" .
      " --in $h{bam_inf} --out $h{bam_outf}";
    
    if ($h{single}) {
        $cmd .= " --single";
    } 

    if ($replace_flag) {
        my $prev_bam = $h{bam_inf};
        $prev_bam =~ s/\.bam/.preRealign.bam/;

        $cmd .= " && mv -f $h{bam_inf} $prev_bam" .
            " && mv -f $h{bam_inf}.bai $prev_bam.bai" .
            " && mv -f $h{bam_outf} $h{bam_inf}";
    }

    $cmd = "($cmd) &> $h{bam_inf}.abra.log";
    print STDERR "\nRealigning with ABRA.\n";
    print STDERR "$cmd\n";

    my $status = system($cmd);
    if ($status) {
        print STDERR "Failed in ABRA realignment.\n";
        return $status;
    }

    if ($replace_flag) {
        return $self->sort_index_bam( bam_inf => $h{bam_inf} );
    }
    else {
        return $self->sort_index_bam( bam_inf => $h{bam_outf} );
    }
}

=head2 remove_duplicate

 Usage   : $obj->remove_duplicate($inbam, $outbam)
 Function: removing duplicates from input bam file that is already marked for duplicates.
 Args    : input bam file, optional output bam file

=cut

sub remove_duplicate {
    my ( $self, $inbam, $outbam ) = @_;

    my $replace = 0;
    if ( !$outbam ) {
        $outbam  = "$inbam.tmp";
        $replace = 1;
    }
    print STDERR "\nRemoving duplicates.\n";
    my $status = system("$self->{samtools} view -b -F 1024 $inbam > $outbam");
    if ( $status == 0 && $replace == 1 ) {
        rename( $outbam, $inbam );
    }
    print STDERR "Failed in removing duplicates in bam.\n" if $status;
    return $status;
}

=head2 fastqReadCount

 Usage   : $obj->fastqReadCount($fastq_file, $gz)
 Function: Count reads in fastq file. If it's gzipped, set gz=1
 Returns : number of reads
 Args    : fastq file, gz flag (1/0)

=cut

sub fastqReadCount {
    my ( $self, $fastq_file, $gz ) = @_;
    my $cmd = $gz ? "gunzip -c $fastq_file|wc -l" : "wc -l $fastq_file";
    my $result = qx($cmd) or quit($self->{errorfile}, "Fastq read counting failed");
    chomp $result;
    return $result / 4;
}

=head2 bamReadCount

 Usage   : $obj->bamReadCount($bamfile)
 Function: Obtain read counts from bam file. The bam file should be marked duplicates.
 Returns : an array of counts
 Args    : input bam file

=cut

sub bamReadCount {
    my ( $self, $bamfile, $dupStat ) = @_;
    my $cmd = $self->{samtools} . " view -c $bamfile";

    my $bam_reads    = qx($cmd 2>/dev/null);
    my $mapped_reads = qx($cmd -F 4 2>/dev/null);
    chomp $bam_reads;
    chomp $mapped_reads;
    my $duplicate_reads = "NA";
    my $uniq_reads      = "NA";
    if ($dupStat) {
        $duplicate_reads = qx($cmd -f 1024 2>/dev/null);
        chomp $duplicate_reads;
        $uniq_reads = $mapped_reads - $duplicate_reads;
    }
    return ( $bam_reads, $mapped_reads, $duplicate_reads, $uniq_reads );
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
    my %h = ( min_overlap => 1, @_ );
    required_args( \%h, 'bam_inf', 'chr', 'start', 'end' );

    my $cnt = 0;
    if ( $h{min_overlap} == 1 ) {
        $cnt =
qx($self->{samtools} view -F 4 -c $h{bam_inf} $h{chr}:$h{start}-$h{end} 2>/dev/null);
    }
    else {
        my $ratio = $h{min_overlap} / ( $h{end} - $h{start} + 1 );
        my $bedfile = "$h{bam_inf}.tmp.region.bed";
        $self->makeBed( $h{chr}, $h{start}, $h{end}, $bedfile );
        my $cmd =
          "$self->{bedtools} intersect -a $h{bam_inf} -b $bedfile -F $ratio -u";
        $cmd .= " | $self->{samtools} view -F 4 -c - ";
        $cnt = qx($cmd) or quit($self->{errorfile}, "Bedtools failed");
        unlink $bedfile;
    }
    chomp $cnt;
    return $cnt;
}

=head2 makeBed

 Usage   : $obj->makeBed(chr=>, start=>, end=>, outfile=>)
 Function: create a bed file, with 0-based coordinates: [start coord, end coord).
 Args    : chr, start, end, outfile. start and end is 1-based.

=cut

sub makeBed {
    my $self = shift;
    my %h    = (@_);
    required_args( \%h, 'chr', 'start', 'end', 'outfile' );

    open( my $outf, ">$h{outfile}" );
    print $outf join( "\t", $h{chr}, $h{start} - 1, $h{end} ) . "\n";
    close $outf;
}

=head2 readStats
 
 Usage   : $obj->readStats(fastq_aref=>[], outfile=>, ...)
 Function: Count reads in different stages
 Args    : fastq_aref, bamstat_aref, sample, outfile, etc
           start and end are 1-based.

=cut 

sub readStats {
    my $self = shift;
    # gz: whether the fastq file is gzipped or not.
    my %h    = (
        gz           => 1,

        # Below are required for region read count
        chr         => '',
        start       => 0,
        end         => 0,
        bam_inf     => '',
        min_overlap => 1,
        @_
    );

    required_args( \%h, 'fastq_aref', 'bamstat_aref', 'sample', 'outfile' );

    open( my $cntf, ">$h{outfile}" );
    print $cntf join( "\t",
        "Sample",      "RawReads",    "QualityReads",
        "MappedReads", "PctMap",      "Duplicates", 
        "PctDup",      "UniqueReads", "AmpliconReads" ) . "\n";

    my $raw_reads = 0;
    foreach my $f ( @{$h{fastq_aref}} ) {
        if ( -s $f ) {
            $raw_reads += $self->fastqReadCount( $f, $h{gz} );
        }
    }

    my ( $bam_reads, $mapped_reads, $duplicate_reads, $uniq_reads ) =
      @{ $h{bamstat_aref} };
    my $pct_map =
      $bam_reads > 0
      ? sprintf( "%.2f", 100 * $mapped_reads / $bam_reads )
      : "NA";
    my $pct_dup =
      $bam_reads > 0 && $duplicate_reads ne 'NA'
      ? sprintf( "%.2f", 100 * $duplicate_reads / $bam_reads )
      : "NA";

    my $region_reads = "NA";
    if ( $h{chr} && $h{start} && $h{end} && $h{bam_inf} ) {
        $region_reads = $self->regionReadCount(
            bam_inf     => $h{bam_inf},
            chr         => $h{chr},
            start       => $h{start},
            end         => $h{end},
            min_overlap => $h{min_overlap}
        );
    }

    print $cntf join( "\t",
        $h{sample},    $raw_reads,  $bam_reads,
        $mapped_reads, $pct_map,    $duplicate_reads, 
        $pct_dup,      $uniq_reads, $region_reads )
      . "\n";
    close $cntf;
}

=head2 chromCount

 Usage   : $obj->chromCount(sample='x', bam_inf=>, outfile=> )
 Function: Calculate the number of reads aligned on different chromosomes
 Args    : sample, bam_inf, outfile

=cut

sub chromCount {
    my $self = shift;
    my %h    = (@_);
    required_args( \%h,, 'sample', 'bam_inf', 'outfile' );

    my $result =
      qx($self->{samtools} view $h{bam_inf} | cut -f 3 | sort | uniq -c);
    open( my $outf, ">$h{outfile}" ) or quit($self->{errorfile}, "Chrom counting failed");;
    print $outf join( "\t", "Sample", "Chromosome", "ReadCount" ) . "\n";
    foreach my $line ( split( /\n/, $result ) ) {
        next if $line !~ /\w/;
        chomp $line;
        my ( $reads, $chr ) = ( $line =~ /(\d+)\s(\S+)/ );
        next if $chr eq '*';
        print $outf join( "\t", $h{sample}, $chr, $reads ) . "\n";
    }
    close $outf;
}

=head2 combineChromCount

 Usage   : $obj->combineChromCount(inf_aref=>[], outfile)
 Function: combine the chromosome read counts across multiple chrom count files
 Args    : inf_aref (array ref of chrom count files), outfile.

=cut

sub combineChromCount {
    my $self = shift;
    my %h    = ('rm'=>0, #remove input files after combined.
                @_);
    required_args (\%h, 'inf_aref', 'outfile');
    my %count;
    foreach my $f ( @{$h{inf_aref}} ) {
        open(my $inf, $f) or die $!;
        my $line=<$inf>;
        while ($line=<$inf>){
            chomp $line;
            my @a = split(/\t/, $line);
            $count{"$a[0]\t$a[1]"} += $a[2];
        }
        close $inf;
        unlink $f if $h{rm};
    }
    open(my $outf, ">$h{outfile}") or die $!;
    print $outf join("\t", "Sample", "Chromosome", "ReadCount") . "\n";
    foreach my $key ( sort keys %count ) {
       print $outf "$key\t" . $count{$key} . "\n";
    }
    close $outf;
}
 
=head2 variantStat

 Usage   : $obj->variantStat(bam_inf=>, outfile=>, )
 Function: Caluculate depth, indel, SNPs in a bam file.
 Args    : bam_inf, ref_fasta, outfile, etc.
	pysamstats must be in PATH or specified. Require python module pysam.
    pysamstats will try to build FASTA index if it is not present, so the
      reference directory should be writable.
=cut

sub variantStat {
    my $self = shift;
    my %h    = (
        max_depth   => 1000000,
        window_size => 1,
        type        => 'variation',
        chr         => '',
        start       => 0,
        end         => 0,
        @_,
    );

    required_args( \%h, 'bam_inf', 'ref_fasta', 'outfile' );
    my $cmd = $self->{pysamstats} . " --type $h{type} --max-depth $h{max_depth}" .
        " --window-size $h{window_size} --fasta $h{ref_fasta}" .
        " --fields chrom,pos,ref,reads_all,matches,mismatches," . 
        "deletions,insertions,A,C,T,G,N";
    if ( $h{chr} && $h{start} > 0 && $h{end} > 0 ) {
        $cmd .= " --chromosome $h{chr} --start $h{start} --end $h{end}";
    }
    $cmd .= " $h{bam_inf} --output $h{outfile}";

    print STDERR "\nCalculating stats of variants using pysamstats.\n";
    print STDERR "$cmd\n" if $self->{verbose};

    if ( system($cmd) ) {
        quit($self->{errorfile}, "Pysamstats failure");
    }
}

=head2 required_args
 
 Usage   : $obj->required_args($href)
 Function: Quit if a required argument is missing.
 Args    : a hash reference

=cut

sub required_args {
    my $href = shift;
    foreach my $arg (@_) {
        if ( !defined $href->{$arg} ) {
            print STDERR "Missing required argument: $arg\n";
        }
    }
}

=head2 targetSeq

 Usage   : $obj->targetSeq(args)
 Function: Find reads that overlap with the target region. 
 Returns : Number of spanning reads
 Args    : bam_inf, chr, target_start, target_end,
           amplicon_seq, amplicon_start, 
			outfile_targetSeq, outfile_indelPct, outfile_indelLen
	target_start and target_end are 1-based and inclusive.
	amplicon_seq is genomic sequence on positive strand.
	amplicon_start uses the 1-based coordinate.

=cut

sub targetSeq {
    my $self = shift;
    my %h    = (
        min_mapq    => 0,
        target_name => '',    # DGKA_CR1
        ref_name    => '',    # hg19
        sample      => '',
        @_
    );

    required_args(
        \%h,                'bam_inf',
        'chr',              'target_start',
        'target_end',       'amplicon_seq',
        'amplicon_start',   'outfile_targetSeq',
        'outfile_indelPct', 'outfile_indelLen'
    );

    open( my $seqf, ">$h{outfile_targetSeq}" );
    open( my $pctf, ">$h{outfile_indelPct}" );
    open( my $lenf, ">$h{outfile_indelLen}" );

    print $seqf join( "\t",
        "ReadName",       "TargetSeq", "IndelStr",
        "OffsetIndelStr", "Strand",    "IndelLength" )
      . "\n";
    print $pctf join( "\t",
        "Sample",      "CrisprSite",   "Reference",  "CrisprRegion",
        "TargetReads", "WtReads",      "IndelReads", "PctWt",
        "PctIndel",    "InframeIndel", "PctInframeIndel" )
      . "\n";
    print $lenf join( "\t",
        "Sample",      "CrisprSite", "CrisprRegion",
        "IndelStr",    "ReadCount",  "ReadPct",
        "IndelLength", "FrameShift", "FlankingSeq" )
      . "\n";

    my $bedfile = "$h{bam_inf}.tmp.target.bed";
    $self->makeBed(
        chr     => $h{chr},
        start   => $h{target_start},
        end     => $h{target_end},
        outfile => $bedfile
    );
    my $cmd = "$self->{bedtools} intersect -a $h{bam_inf} -b $bedfile" . 
        " -F 1 -u | $self->{samtools} view -";

    open( P, "$cmd|" ) or quit($self->{errorfile}, "Bedtools failed");

    # reads spanning target region that meet min_mapq 
    my $overlap_reads = 0;

    # among total reads, those with at least 1 base of indel inside target region.
    my $indel_reads         = 0;
    my $inframe_indel_reads = 0;
    my %freqs = (WT=>0);    # frequencies of alleles

    while ( my $line = <P> ) {
        my @info =
          $self->extractReadRange( $line, $h{chr}, $h{target_start},
            $h{target_end}, $h{min_mapq} );
        next if !@info;

        $overlap_reads++;

        if ( $info[2] =~ /[ID]/ ) {
            $indel_reads++;
            $inframe_indel_reads++ if $info[5] % 3 == 0;
            $freqs{ $info[2] }++;
        }
        else {
            $freqs{WT}++;
        }

        print $seqf join( "\t", @info ) . "\n";
    }    # end while

    unlink $bedfile;

    ## Output read counts

    my $wt_reads  = $overlap_reads ? $overlap_reads - $indel_reads : 0;
    my $pct_wt    = $overlap_reads ? sprintf( "%.2f", $wt_reads * 100 / $overlap_reads ) : 0;
    my $pct_indel = $overlap_reads ? sprintf( "%.2f", 100 - $pct_wt ) : 0;
    my $pct_inframe = $overlap_reads ? 
      sprintf( "%.2f", $inframe_indel_reads * 100 / $overlap_reads ) : 0;

    print $pctf join( "\t",
        $h{sample},     $h{target_name},
        $h{ref_name},   "$h{chr}:$h{target_start}-$h{target_end}",
        $overlap_reads, $wt_reads,
        $indel_reads,   $pct_wt,
        $pct_indel,     $inframe_indel_reads,
        $pct_inframe )
      . "\n";

    ## Output allele frequencies in descending order
    foreach my $key ( sort { $freqs{$b} <=> $freqs{$a} } keys %freqs ) {
        my $reads = $freqs{$key};
        my $pct = $overlap_reads ? sprintf( "%.2f", $reads * 100 / $overlap_reads ) : 0;

        my $indel_len   = 0;
        my $frame_shift = "N";
        if ( $key ne "WT" ) {
            $indel_len = _getIndelLength($key);
            $frame_shift = $indel_len % 3 ? "Y" : "N";
        }

        my $flank_seq =
          $self->getFlankingSeq( $h{amplicon_seq}, $h{amplicon_start},
            $h{target_start}, $h{target_end}, $key );

        print $lenf join( "\t",
            $h{sample}, $h{target_name},
            "$h{chr}:$h{target_start}-$h{target_end}",
            $key, $reads, $pct, $indel_len, $frame_shift, $flank_seq )
          . "\n";
    }
}

=head2 extractReadRange

 Usage   : $obj->extractReadRange($sam_record, $chr, $start, $end, $min_mapq)
 Function: extract read sequence within a range 
 Args    : $sam_record, $chr, $start, $end, $min_mapq 
	start and end are 1-based and inclusive.

=cut

sub extractReadRange {
    my ( $self, $sam_record, $chr, $start, $end, $min_mapq ) = @_;
    my (
        $qname, $flag,  $refchr,   $align_start,
        $mapq,  $cigar, $mate_chr, $mate_start,
        $tlen,  $seq,   $qual
    ) = split( /\t/, $sam_record );

    if ( ($chr ne $refchr) or ($min_mapq && $mapq < $min_mapq) ) {
        return;
    }

    # 101900216:101900224:D:-:101900224:101900225:I:G
    my $indelstr     = '';    # position are 1-based.
    my $indel_length = 0;

    # read sequence comparable to reference but with 
    # insertion removed and deletion added back.
    my $newseq;
    my $chr_pos = $align_start - 1;    # pos on chromosome
    my $seq_pos = 0;                   # position on read sequence

    # split cigar string between number and letter
    my @cig = split( /(?<=\d)(?=\D)|(?<=\D)(?=\d)/, $cigar );

    for ( my $i = 0 ; $i < @cig - 1 ; $i += 2 ) {
        my $len    = $cig[$i];
        my $letter = $cig[ $i + 1 ];
        if ( $letter eq "S" ) {
            $seq_pos += $len;
        }
        elsif ( $letter eq "M" ) {
            $newseq .= substr( $seq, $seq_pos, $len );
            $seq_pos += $len;
            $chr_pos += $len;
        }
        elsif ( $letter eq "D" ) {
            $newseq .= '-' x $len;
            my $del_start = $chr_pos + 1;
            $chr_pos += $len;

            # keep the deletion if it overlaps the target region by 1 base.
            if ( _isOverlap( $start, $end, $del_start, $chr_pos, 1 ) ) {
                $indelstr .= "$del_start:$chr_pos:D:-:";
                $indel_length -= $len;
            }
        }
        elsif ( $letter eq "I" ) {
            my $inserted_seq = substr( $seq, $seq_pos, $len );
            $seq_pos += $len;

            # keep the insertion if it overlaps the target region by 1 base.
            if ( _isOverlap( $start, $end, $chr_pos, $chr_pos + 1, 1 ) ) {
                $indelstr .= $chr_pos . ":" . ( $chr_pos + 1 ) . ":I:$inserted_seq:";
                $indel_length += $len;
            }
        }    # end if
    }    # end for

    # sequence in specified range
    my $range_seq = substr( $newseq, $start - $align_start, $end - $start + 1 );

    # 8:16:D:-:16:17:I:G  postions are 1-based.
    my $offset_indelstr;    # indel str with offset locations.
    foreach my $e ( split( /:/, $indelstr ) ) {
        $e = $e - $start + 1 if $e =~ /^\d+$/;
        $offset_indelstr .= $e . ":";
    }

    $indelstr        =~ s/:$//;
    $offset_indelstr =~ s/:$//;

    my $strand = $flag & 16 ? '-' : '+';
    return (
        $qname,           $range_seq, $indelstr,
        $offset_indelstr, $strand,    $indel_length
    );
}

sub _getIndelLength {
    my $indelstr = shift;
    ## e.g. 56330828:56330829:D::56330837:56330838:I:CCC
    my @a = split( /:/, $indelstr );
    my $len = 0;
    for ( my $i = 0 ; $i < @a ; $i += 4 ) {
        if ( $a[ $i + 2 ] eq "D" ) {
            $len -= $a[ $i + 1 ] - $a[$i] + 1;
        }
        elsif ( $a[ $i + 2 ] eq "I" ) {
            $len += length( $a[ $i + 3 ] );
        }
    }
    return $len;
}

sub _isOverlap {
    my ( $subj_start, $subj_end, $query_start, $query_end, $min_overlap ) = @_;
    $min_overlap //= 1;

    my %subj;
    for ( my $i = $subj_start ; $i <= $subj_end ; $i++ ) {
        $subj{$i} = 1;
    }

    my $overlap = 0;
    for ( my $i = $query_start ; $i <= $query_end ; $i++ ) {
        $overlap++ if $subj{$i};
    }

    return $overlap >= $min_overlap ? 1 : 0;
}

=head2 categorizeHDR

 Usage   : $obj->categorizeHDR(bam_inf=>, ...)
 Function: To classify oligos in HDR (homology directed repair) region into different categories 
 Args    : bam_inf, chr, base_changes, sgRNA_start, sgRNA_end, sample, stat_outf, ref_fasta, var_outf 
	base_changes is a comma-separated strings of positons and bases. Format: <pos><base>,...
	for example, 101900208C,101900229G,101900232C,101900235A. Bases are on positive strand, and 
	are intended new bases, not reference bases. Coorindates are 1-based. 
        sgRNA_start and sgRNA_end are 1-based. The region to examine HDR covers sgRNA and all HDR bases.

=cut

sub categorizeHDR {
    my $self = shift;
    my %h    = (
        min_mapq => 0,
        @_
    );

    required_args( \%h, 'bam_inf', 'chr', 'base_changes', 
        'sgRNA_start', 'sgRNA_end', 'sample',
        'stat_outf', 'ref_fasta', 'var_outf');

    my $sample = $h{sample};
    my $chr    = $h{chr};

    # HDR region range: covers sgRNA region and all intended mutation bases
    my $hdr_start = $h{sgRNA_start}; # initialization
    my $hdr_end = $h{sgRNA_end}; # initialization 

    # intended base changes
    my %alt;    # pos=>base
    $h{base_changes} =~ s/ //g; 
    foreach my $mut ( split /,/, $h{base_changes} ) {
        my ( $pos, $base ) = ( $mut =~ /(\d+)(\D+)/ );
        $alt{$pos} = uc($base);
        if ( $pos < $hdr_start ) {
            $hdr_start = $pos;
        } elsif ( $pos > $hdr_end ) {
            $hdr_end = $pos;
        }
    }

    my $outdir = dirname( $h{stat_outf} );
    make_path($outdir);

    # create bed file spanning the HDR SNPs. Position format: [Start, end).
    my $bedfile   = "$outdir/$sample.hdr.bed";
    my @pos       = sort { $a <=> $b } keys %alt;

    $self->makeBed(
        chr     => $h{chr},
        start   => $hdr_start,
        end     => $hdr_end,
        outfile => $bedfile
    );

    # create bam file containing HDR region.
    my $hdr_bam = "$outdir/$sample.hdr.bam";

    my $samtools = $self->{samtools};
    my $cmd = "$self->{bedtools} intersect -a $h{bam_inf} -b $bedfile -F 1 -u";
    $cmd .= " > $hdr_bam && $samtools index $hdr_bam";
    if ( system($cmd) ) {
        print STDERR "Failed to create $hdr_bam\n";
        quit($self->{errorfile}, "Bedtools failed");
    }

    ## create HDR seq file
    my $hdr_seq_file = "$outdir/$sample.hdr.seq";
    $self->extractHDRseq( $hdr_bam, $chr, $hdr_start, $hdr_end, $hdr_seq_file,
        $h{min_mapq} );

    # calculate the HDR rates
    $self->rateHDR(base_changes=>$h{base_changes}, hdr_seq_file=>$hdr_seq_file, 
        seq_start=>$hdr_start, sample=>$sample, stat_outf=>$h{stat_outf});


    # calculate SNP rate in HDR region. Require all bases in HDR region to be in the same read.
    $self->variantStat( bam_inf=>$hdr_bam, ref_fasta=>$h{ref_fasta}, outfile=>$h{var_outf}, 
                        chr=> $h{chr}, start=>$hdr_start, end=>$hdr_end);	
	
    # remove records before and after HDR region.
    open(my $inf, $h{var_outf}) or die "Cannot open $h{var_outf}\n";
    open(my $outf, ">$h{var_outf}.tmp") or die $!;
    my $line=<$inf>; 
    print $outf $line;
    while ($line=<$inf>) {
        my @a=split(/\t/, $line);
        if ( $a[1] >= $hdr_start and $a[1] <= $hdr_end ) {
            print $outf $line;
        }
    }
    close $outf;
    close $inf;
    rename("$h{var_outf}.tmp", $h{var_outf});
}

=head2 rateHDR

 Usage   : $obj->rateHDR(base_changes=>, ...)
 Function: To calculate rate of HDR (homology directed repair) 
 Args    : base_changes, hdr_seq_file, seq_start, outf 
	base_changes: is a comma-separated strings of positons and bases. Format: <pos><base>,...
	  for example, 101900208C,101900229G,101900232C,101900235A. Bases are on positive strand, and 
	  are intended new bases, not reference bases. 
	hdr_seq_file: contains annotations of sequence covering HDR region.
	seq_start: the 1-based chr pos of the first base of the hdr_seq.
	sample: sampe name
	outf: output file

=cut

sub rateHDR {
    my $self = shift;
    my %h    = (
        @_
    );

    required_args( \%h, 'base_changes', 'hdr_seq_file', 'seq_start', 
         'sample', 'stat_outf');

    # intended base changes
    my %alt;    # pos=>base
    foreach my $mut ( split /,/, $h{base_changes} ) {
        my ( $pos, $base ) = ( $mut =~ /(\d+)(\D+)/ );
        $alt{$pos} = uc($base);
    }
    print STDERR Dumper(\%alt) . "\n" if $h{verbose};

    my @pos       = sort { $a <=> $b } keys %alt;

    my $total = 0;                             # total reads
    my $perfect_oligo = 0;                     # perfect HDR reads.
    my $edit_oligo = 0;    
      # reads with 1 or more desired bases, but also width indels
    my $partial_oligo = 0;    
      # reads with some but not all desired bases, no indel.
    my $non_oligo = 0;    
      # reads without any desired base changes, regardless of indel

    open( my $inf, $h{hdr_seq_file} );
    open( my $annotf, ">$h{hdr_seq_file}.annot");
    print $annotf join("\t", "Read", "sgRNA+HDR Region Seq", "IndelStr",
                     "Offset IndelStr", "Strand", "IndelLength",
                     "Bases at HDR Pos", "#Repaired", "Category") . "\n";

    while ( my $line = <$inf> ) {
        next if $line !~ /\w/;
        chomp $line;
        my ( $qname, $hdr_seq, $indelstr ) = split( /\t/, $line );

        my $isEdited = $indelstr =~ /[ID]/ ? 1 : 0;

        my @bases = split( //, $hdr_seq );
        my $alt_cnt = 0;    # snp base cnt
        my $hdr_str = ''; # concatenation of bases at HDR locations
        for (my $i=0; $i<@bases; $i++) {
            my $loc = $i + $h{seq_start};
            if ( $loc >= $pos[0] and $loc <= $pos[-1] ) {
                if ( $alt{$loc} ) {
                    $hdr_str .= $bases[$i]; # assuming study of point mutations
                    if ( $bases[$i] eq $alt{$loc} ) {
                        $alt_cnt++;
                    }
                } 
            }
        }

        my $type;
        if ( $alt_cnt == 0 ) {
            $non_oligo++;
            $type = "NonOligo";
        }
        else {
            if ($isEdited) {
                $edit_oligo++;
                $type = "Edit";
            }
            else {
                if ( $alt_cnt == scalar(@pos) ) {
                    $perfect_oligo++;
                    $type = "Perfect";
                }
                else {
                    $partial_oligo++;
                    $type = "Partial";
                }
            }
        }
        print $annotf join("\t", $line, $hdr_str, $alt_cnt, $type) ."\n";
        $total++;

    }    # end while
    close $annotf;
    if ( $total ) {
        rename("$h{hdr_seq_file}.annot", $h{hdr_seq_file});
    } 

    open( my $outf, ">$h{stat_outf}" );

    my @cnames = ( "PerfectOligo", "EditedOligo", "PartialOligo", "NonOligo" );
    my @pct_cnames;
    foreach my $cn (@cnames) {
        push( @pct_cnames, "Pct$cn" );
    }

    my @values = ( $perfect_oligo, $edit_oligo, $partial_oligo, $non_oligo );
    my @pcts;
    foreach my $v (@values) {
        push( @pcts, $total ? sprintf( "%.2f", $v * 100 / $total ) : 0 );
    }

    print $outf join( "\t", "Sample", "TotalReads", @cnames, @pct_cnames)."\n";
    print $outf join( "\t", $h{sample}, $total, @values, @pcts ) . "\n";

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
# start, end are 1-based inclusive. They are the first and last position
# of intended base change region of HDR
sub extractHDRseq {
    my ( $self, $hdr_bam, $chr, $hdr_start, $hdr_end, $out_hdr_seq, $min_mapq )
      = @_;

    open( my $seqf, ">$out_hdr_seq" );
    open( my $pipe, "$self->{samtools} view $hdr_bam|" );
    while ( my $line = <$pipe> ) {
        my @info =
          $self->extractReadRange( $line, $chr, $hdr_start, $hdr_end,
            $min_mapq );
        print $seqf join( "\t", @info ) . "\n" if @info;
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
    my ( $self, $bedfile, $region_name ) = @_;
    open( my $fh, $bedfile );
    while (<$fh>) {
        next if ( $_ =~ /^\#/ or $_ !~ /\w/ );
        chomp;
        my @a = split /\t/;
        if ( !$region_name or $region_name eq $a[3] ) {
            return @a;
        }
    }
    close $fh;
}

=head2 run

 Usage   : run($cmd, $err_msg)
 Function: Run command, print error message if any   
 Returns : Job status code 
 Args    : cmd,  error string 

=cut

sub run {
    my ( $cmd, $err_msg ) = @_;
    my $status = system($cmd);
    if ($status) {
        print STDERR $err_msg if $err_msg;
    }
    return $status;
}

=head2 getFlankingSeq
 
 Usage   : getFlankingSeq($amplicon_seq, $amplicon_start, $target_start, $target_end, $indelstr)
           amplicon_start is where the 1st base of amplicon_seq is in genomic chromosome, 1-based.
           indelstr is 1-based, e.g. 52272278:52272279:I:ATTTCA:52272290:52272291:D:.
 Function: Find the flanking sequence witout the deleted bases but with inserted bases, if any   
 Returns : sequence string 
 Args    : amplicon_seq, amplicon_start, indelstr 

=cut

sub getFlankingSeq {
    my ( $self, $amplicon_seq, $amplicon_start, $target_start, $target_end,
        $indelstr )
      = @_;

   # indelstr is WT for wild type. For indels, it has D or I as described above.
    my $flank_seq = "";

# WT. No indelstr. Extract sequence from $target_start-$FLANK_LEN to $target_end+$FLANK_LEN
# Has indel. Extract Left most indel pos - $FLANK_LEN to right most indel pos + $FLANK_LEN
# Remove deleted bases and add inserted bases.

    my %indels;    # {loc=>1 for deletion, loc=>inserted_seq for insertion}
    my $left_pos  = $target_start;
    my $right_pos = $target_end;

    my $FLANK_LEN = 60;
    if ( $indelstr =~ /[DI]/ ) {
        $FLANK_LEN = 30;
        my @tmp = split( /:/, $indelstr );
        $left_pos  = $tmp[0];
        $right_pos = $tmp[ $#tmp - 2 ];

        for ( my $i = 0 ; $i < @tmp ; $i += 4 ) {
            if ( $tmp[ $i + 2 ] eq "I" ) {

                # insertion
                $indels{ $tmp[$i] } = $tmp[ $i + 3 ];
            }
            else {

                # deletions
                for ( my $p = $tmp[$i] ; $p <= $tmp[ $i + 1 ] ; $p++ ) {
                    $indels{$p} = 1;
                }
            }
        }
    }

    $left_pos -= $FLANK_LEN;
    $right_pos += $FLANK_LEN;
    if ( $left_pos < $amplicon_start ) {
        $left_pos = $amplicon_start;
    }

    my $amplicon_end = $amplicon_start + length($amplicon_seq) - 1;
    if ( $right_pos > $amplicon_end ) {
        $right_pos = $amplicon_end;
    }

    my @bases = split( //, $amplicon_seq );
    my @flank_bases;
    for ( my $p = $left_pos ; $p <= $right_pos ; $p++ ) {

        # Include non-deleted bases
        if ( !$indels{$p} or $indels{$p} != 1 ) {
            push( @flank_bases, $bases[ $p - $amplicon_start ] );
        }

        # Add inserted bases
        if ( $indels{$p} =~ /[ATCGN]/i ) {
            push( @flank_bases, $indels{$p} );
        }
    }

    return join( '', @flank_bases );
}

sub quit {
    my ($flag_file, $msg) = @_;
    if ( $msg ) {
        qx(echo $msg > $flag_file);
    } else {
        qx(touch $flag_file);
    }
    exit 1;
}

1;
