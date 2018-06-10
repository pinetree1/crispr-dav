#!/usr/bin/env perl
# Process one sample
# Author: X. Wang

use 5.010;
use strict;
use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin/Modules";
use NGS;
use Exon;
use Util;
use Data::Dumper;
use File::Path qw(make_path);

my %h = get_input();
print STDERR Dumper( \%h ) if $h{verbose};

my $outdir        = $h{outdir};
my $sample        = $h{sample};
my $read1_outfile = "$outdir/$sample.R1.fastq.gz";
my $read2_outfile = "$outdir/$sample.R2.fastq.gz";
my $merge_outfile = "$outdir/$sample.MG.fastq.gz";
my $bamfile       = "$outdir/$sample.bam";
my $readcount = "$outdir/$sample.cnt";    # to combine into readcount.txt
my $readchr   = "$outdir/$sample.chr";
my $varstat = "$outdir/$sample.var"; # to use for amplicon-wide plots, snp plots
my $fail_flag = "$outdir/$sample.failed";

## file size 0
if ( -z $h{read1fastq} or ( $h{read2fastq} && -z $h{read2fastq} ) ) {
    print STDERR "\nError: Source fastq file empty\n"; 
    quit($fail_flag, "Source fastq file empty");
}

if ( $h{merge} eq "Y"  && -f $h{read1fastq} && !-f $h{read2fastq} ) {
    print STDERR "\nNo merge will be done because only one fastq file is provided.\n";
    $h{merge} = "N";
}
	
my $ngs = new NGS(
    java     => $h{java},
    samtools => $h{samtools},
    bedtools => $h{bedtools},
    bwa      => $h{bwa},
    prinseq  => $h{prinseq},
    pysamstats=> $h{pysamstats},
    flash    => $h{flash},
    tmpdir   => $h{tmpdir},
    verbose  => $h{verbose},
    errorfile=> $fail_flag 
);

make_path($outdir) if !-d $outdir;

my $ampbed = "$outdir/$sample.amp.bed";
$ngs->makeBed(
    chr     => $h{chr},
    start   => $h{amplicon_start},
    end     => $h{amplicon_end},
    outfile => $ampbed
);

if ( $h{merge} ne "Y" or !-f $h{read2fastq}) {

    ## filter fastq files
    my $status = $ngs->filter_reads(
        read1_inf     => $h{read1fastq},
        read2_inf     => $h{read2fastq},
        read1_outf    => $read1_outfile,
        read2_outf    => $read2_outfile,
        min_qual_mean => $h{min_qual_mean},
        min_len       => $h{min_len},
        ns_max_p      => $h{ns_max_p}
    );

    if ( $status == 1 ) {
        quit($fail_flag, "No quality reads after filtering");
    } elsif ( $status == 2 ) {
        quit($fail_flag, "Other filtering error");
    }

    ## Alignment and processing to create bam file
    my @bamstats = $ngs->create_bam(
        sample             => $sample,
        read1_inf          => $read1_outfile,
        read2_inf          => $read2_outfile,
        idxbase            => $h{idxbase},
        bam_outf           => $bamfile,
        abra               => $h{abra},
        target_bed         => $ampbed,
        ref_fasta          => $h{ref_fasta},
        realign            => $h{realign},
        picard             => $h{picard},
        remove_duplicate   => $h{unique},
        chromCount_outfile => $readchr
    );

    quit($fail_flag, "Alignment error") if scalar(@bamstats) == 1;

    ## Count reads in processing stages
    $ngs->readStats(
        bamstat_aref => \@bamstats,
        fastq_aref   => [$h{read1fastq}, $h{read2fastq}],
        gz           => 1,
        bam_inf      => $bamfile,
        chr          => $h{chr},
        start        => $h{amplicon_start},
        end          => $h{amplicon_end},
        sample       => $sample,
        outfile      => $readcount
    );

} else {
    # merge paired-end reads
    my $status = $ngs->merge_reads(
        r1_fastq_inf  => $h{read1fastq},
        r2_fastq_inf  => $h{read2fastq},
        outdir => $outdir,
        prefix => $sample,
        params => '-m 15 -M 300'
    );

    quit($fail_flag, "Failed in merging paired-end reads") if $status; 

    # filter merged fastq file
    my $merged_fastq = "$outdir/$sample.extendedFrags.fastq.gz";
    my $merged_filt  = "$outdir/$sample.extendedFrags.filt.fastq.gz";
    if ( -s $merged_fastq ) {
        $status = $ngs->filter_reads (
            read1_inf     => $merged_fastq,
            read1_outf    => $merged_filt,
            min_qual_mean => $h{min_qual_mean},
            min_len       => $h{min_len},
            ns_max_p      => $h{ns_max_p}
        );

        if ( $status == 2 ) {
            quit($fail_flag, "Failed in filtering merged fastq file");
        }
    }

    # filter un-merged fastq file
    my $un_merged_fastq1 = "$outdir/$sample.notCombined_1.fastq.gz";
    my $un_merged_fastq2 = "$outdir/$sample.notCombined_2.fastq.gz";
    my $un_merged_filt1 = "$outdir/$sample.notCombined_1.filt.fastq.gz";
    my $un_merged_filt2 = "$outdir/$sample.notCombined_2.filt.fastq.gz";
    if ( -s $un_merged_fastq1 ) {
        $status = $ngs->filter_reads (
            read1_inf     => $un_merged_fastq1,
            read2_inf     => $un_merged_fastq2,
            read1_outf    => $un_merged_filt1,
            read2_outf    => $un_merged_filt2,
            min_qual_mean => $h{min_qual_mean},
            min_len       => $h{min_len},
            ns_max_p      => $h{ns_max_p}
        );

        if ( $status == 2 ) {
            quit($fail_flag, "Failed in filtering un-merged fastq files");
        }
    }

    # align merged fastq file
    my @mg_bamstats;
    my $merged_filt_bamfile = "$outdir/$sample.extendedFrags.bam"; 
    if ( -s $merged_filt ) {
        @mg_bamstats = $ngs->create_bam(
            sample             => $sample,
            read1_inf          => $merged_filt,
            idxbase            => $h{idxbase},
            bam_outf           => $merged_filt_bamfile,
            abra               => $h{abra},
            target_bed         => $ampbed,
            ref_fasta          => $h{ref_fasta},
            realign            => $h{realign},
            picard             => $h{picard},
            remove_duplicate   => $h{unique},
            chromCount_outfile => "$readchr.merge"
        );
    }

    # align un-merged fastq files
    my @um_bamstats;
    my $un_merged_filt_bamfile = "$outdir/$sample.notCombined.bam"; 
    my @um_bamstats = $ngs->create_bam(
        sample             => $sample,
        read1_inf          => $un_merged_filt1,
        read2_inf          => $un_merged_filt2,
        idxbase            => $h{idxbase},
        bam_outf           => $un_merged_filt_bamfile,
        abra               => $h{abra},
        target_bed         => $ampbed,
        ref_fasta          => $h{ref_fasta},
        realign            => $h{realign},
        picard             => $h{picard},
        remove_duplicate   => $h{unique},
        chromCount_outfile => "$readchr.un_merge"
    );

    # combined two bam file
    $ngs->merge_bam(bam_inf_aref=>[$merged_filt_bamfile, $un_merged_filt_bamfile],
                    bam_outf=>$bamfile, 
                    sort_index=>1);

    ## Count reads in processing stages
    my @bamstats;
    for (my $i=0; $i< @mg_bamstats; $i++) {
        if ( $mg_bamstats[$i] eq "NA" or $um_bamstats[$i] eq "NA" ) {
            $bamstats[$i] = "NA";
        } else {
            $bamstats[$i] = $mg_bamstats[$i] + $um_bamstats[$i];
        }
    }

    $ngs->readStats(
        bamstat_aref => \@bamstats,
        fastq_aref => [$merged_fastq, $un_merged_fastq1, $un_merged_fastq2],
        gz           => 1,
        bam_inf      => $bamfile,
        chr          => $h{chr},
        start        => $h{amplicon_start},
        end          => $h{amplicon_end},
        sample       => $sample,
        outfile      => $readcount
    );

    # Combine chr counts from merged and un-merged counts
    $ngs->combineChromCount(inf_aref=>["$readchr.merge", "$readchr.un_merge"], 
                          outfile=>$readchr); 

    clean_up( $merged_filt, $un_merged_filt1, $un_merged_filt2, 
        $merged_filt_bamfile,"$merged_filt_bamfile.bai", 
        $un_merged_filt_bamfile, "$un_merged_filt_bamfile.bai", 
        "$readchr.merge", "$readchr.un_merge"
        );
}
unlink $ampbed;

## Gather variant stats in amplicon.
$ngs->variantStat(
    bam_inf    => $bamfile,
    ref_fasta  => $h{ref_fasta},
    outfile    => $varstat,
    chr        => $h{chr},
    start      => $h{amplicon_start},
    end        => $h{amplicon_end}
);

quit($fail_flag, "Pysamstats error") if -z $varstat;

my $plot_ext = $h{high_res} ? "tif" : "png";

# amplicon sequence on positive strand
my $obj = new Exon(
    'fasta_file' => $h{ref_fasta},
    'seqid'      => $h{chr},
    'samtools'   => $h{samtools}
);
my $amplicon_seq =
  $obj->getSeq( 'start' => $h{amplicon_start}, 'end' => $h{amplicon_end} );

## Determine indel pct and length in each CRISPR site(target)
for my $target_name ( sort split( /,/, $h{target_names} ) ) {
    print STDERR "\nCreating plots and results for CRISPR $target_name ...\n";

    my ( $chr, $target_start, $target_end, $t1, $t2, $strand, $hdr_changes ) =
      $ngs->getRecord( $h{target_bed}, $target_name );
    $target_start ++; # now 1-based

    ## create plots of coverage, insertion and deletion on amplicon
    my $cmd = "$h{rscript} $Bin/Rscripts/amplicon.R --inf=$varstat" .
        " --outf=$outdir/$sample.$target_name  --sample=$sample" . 
        " --hstart=$target_start --hend=$target_end" .
        " --chr=$h{genome} $chr --ampStart=$h{amplicon_start}" .
        " --ampEnd=$h{amplicon_end}"; 
    $cmd .= " --high_res=$h{high_res}" if $h{high_res};
    print STDERR
      "\nPlotting amplicon coverage and indel frequencies.\n";
    Util::run( $cmd, "Failed to generate amplicon-wide plots",
        $h{verbose}, $fail_flag );

    ## create a plot of base changes in crispr site and surronding regions, but does not require
    ## all bases at different positions to be on the same read
    my $rangeStart = $target_start - $h{wing_length};
    my $rangeEnd   = $target_end + $h{wing_length};
    $cmd = "$h{rscript} $Bin/Rscripts/snp.R --inf=$varstat" .
        " --outf=$outdir/$sample.$target_name.snp.$plot_ext" . 
        " --outtsv=$outdir/$sample.$target_name.snp" .
        " --sample=$sample" . 
        " --hstart=$target_start --hend=$target_end" .
        " --chr=$h{genome} $chr --rangeStart=$rangeStart" .
        " --rangeEnd=$rangeEnd";
    $cmd .= " --high_res=$h{high_res}" if $h{high_res};
    print STDERR "\nPlotting SNP data.\n" ;
    Util::run( $cmd, "Failed to generate base-change plot",
        $h{verbose}, $fail_flag );


    ## For target and indels
    my $tseqfile = "$outdir/$sample.$target_name.tgt";
    my $pctfile  = "$outdir/$sample.$target_name.pct";
    my $lenfile  = "$outdir/$sample.$target_name.len";
    my $hdrfile  = "$outdir/$sample.$target_name.hdr";
    my $hdr_var   = "$outdir/$sample.$target_name.hdr.var";

    my $target_reads = $ngs->targetSeq(
        bam_inf           => $bamfile,
        sample            => $sample,
        ref_name          => $h{genome},
        target_name       => $target_name,
        chr               => $chr,
        target_start      => $target_start,
        target_end        => $target_end,
        min_mapq          => $h{min_mapq},
        amplicon_seq      => $amplicon_seq,
        amplicon_start    => $h{amplicon_start},
        outfile_targetSeq => $tseqfile,
        outfile_indelPct  => $pctfile,
        outfile_indelLen  => $lenfile
    );

    ## Determine HDR efficiency
    if ($hdr_changes) {
        $ngs->categorizeHDR(
            bam_inf      => $bamfile,
            chr          => $chr,
            base_changes => $hdr_changes,
            sgRNA_start  => $target_start,
            sgRNA_end    => $target_end,
            sample       => $sample,
            min_mapq     => $h{min_mapq},
            stat_outf    => $hdrfile,
            ref_fasta    => $h{ref_fasta},
            var_outf     => $hdr_var 
        );

        ## create a plot of base changes in HDR regions and require
        ## all bases at different positions to be on the same read
        $cmd = "$h{rscript} $Bin/Rscripts/snp.R --inf=$hdr_var" .
            " --outf=$outdir/$sample.$target_name.hdr.snp.$plot_ext" . 
            " --outtsv=$outdir/$sample.$target_name.hdr.snp" .
            " --sample=$sample" . 
            " --hstart=$target_start --hend=$target_end" .
            " --chr=$h{genome} $chr --sameRead=1" . 
        	" --rangeStart=$rangeStart --rangeEnd=$rangeEnd";
        $cmd .= " --high_res=$h{high_res}" if $h{high_res};
        print STDERR "\nPlotting HDR SNP data.\n" ;
        Util::run( $cmd, "Failed to generate HDR base-change plot",
            $h{verbose}, $fail_flag );

    }

    # OK to continue processing even if there is no spanning read.

    ## prepare data for alignment visualization by Canvas Xpress.
    if ( !$h{nocx} ) {
        my $canvasfile = "$outdir/$sample.$target_name.can";
        my $cmd = "$Bin/cxdata.pl --ref_fasta $h{ref_fasta}" . 
            " --refGene $h{refGene} --refseqid $h{refseqid}" .
            " --samtools $h{samtools} $lenfile $canvasfile";
        print STDERR
          "\nPreparing data for alignment visualization by Canvas Xpress.\n";
        Util::run( $cmd, "Failed to generate data for Canvas Xpress",
            $h{verbose}, $fail_flag );
    }

    ## create plots of allele frequencies 
    $cmd = "$h{rscript} $Bin/Rscripts/allele.R --inf=$lenfile" . 
      " --sample=$sample --outf=$outdir/$sample.$target_name.len.$plot_ext";
    $cmd .= " --high_res=$h{high_res}" if $h{high_res};
    print STDERR "\nPlotting allele frequency.\n";
    Util::run( $cmd, "Failed to generate allele frequency plot",
        $h{verbose}, $fail_flag );

}

if ( !-f $fail_flag ) {
    qx(touch $outdir/$sample.done);
    print STDERR "\nProcessing completed!\n";
}

sub get_input {
    my $usage = "\nUsage: $0 [options] sampleName read1FastqFile outdir

	Fastq files must be gzipped.

	All options are required unless indicated otherwise or has default.

	--picard         <str> Optional. Path to picard-tools directory containing various jar files
	--abra           <str> Path of ABRA jar file.
	--prinseq        <str> Path of prinseq script. Make sure it is executable.
	--samtools       <str> Path of samtools. Default: executable in PATH
	--bwa            <str> Path of bwa. Default: executable in PATH. Make sure it supports mem -M
	--java           <str> Path of java. Default: executable in PATH. Version 1.7 or higher.
	--bedtools       <str> Path of bedtools 2.25. Default: executable in PATH. 
                           Make sure intersect command supports -F option.
	--pysamstats     <str> Path of pysamstats. Default: executable in PATH.
	--rscript        <str> Path of Rscript. Default: executable in PATH.
	--flash          <str> Path of flash2. Default: executable in PATH.
	--tmpdir         <str> Path of temporary directory. Default: /tmp 

	--read2fastq     <str> Optional. Fastq file of read2
	--merge          Y (Default) or N. Merge paired-end reads.

	--min_qual_mean  <int> prinseq parameter. Default: 30
	--min_len        <int> prinseq parameter. Default: 50
	--ns_max_p       <int> prinseq parameter. Default: 3

	--realign        Optional. Realign reads using ABRA. 
	--min_mapq       <int> Optional. Minimum mapping score for reads to be selected.

	--genome         <str> Genome name.		
	--idxbase        <str> Base name of bwa index.
	--ref_fasta      <str> Reference fasta file.
	--refGene        <str> UCSC refGene formatted-file containing transcript/CDS/exon coordinates.
	--refseqid       <str> Refseq gene name which must exist in the refGene file.
	
	--chr            <str> chr sequence ID in genome fasta file
	--amplicon_start <int> amplicon start position. 1-based
	--amplicon_end   <int> amplicon end position. 1-based.

	--target_bed     <int> A bed file of CRISPR sites. 0-based coordinates. End is exclusive.
	--target_names   <str> Names of the CRISPR sites separated by comma.

	--wing_length    <int> Number of bases on each side of CRISPR to show SNP. Default: 40
	--nocx           Do not create canvasXpress alignment data 
	--high_res       Create high resolution tiff file.
	--verbose        Optional. For debugging.	
	--help           Optional. To show this message
";

    my %h;
    GetOptions(
        \%h,                'picard=s',
        'abra=s',           'prinseq=s',
        'samtools=s',       'bwa=s',
        'java=s',           'bedtools=s',
        'pysamstats=s',     'rscript=s',
        'tmpdir=s',         'read2fastq=s',
        'flash=s',          'merge=s',
        'unique',           'realign',
        'min_mapq=i',       'min_qual_mean=i',
        'min_len=i',        'ns_max_p=i',
        'genome=s',         'idxbase=s',
        'ref_fasta=s',      'refGene=s',
        'refseqid=s',       'chr=s',
        'amplicon_start=i', 'amplicon_end=i',
        'target_bed=s',     'target_names=s',
        'wing_length=s',    'nocx',
        'high_res',         'verbose',
        'help'
    );

    die $usage if @ARGV != 3 or $h{help};
    ( $h{sample}, $h{read1fastq}, $h{outdir} ) = @ARGV;

    for my $f ( $h{read1fastq}, $h{read2fastq} ) {
        if ( $f && $f !~ /\.gz$/ ) {
            die "$f must be gzipped and with .gz extension.\n";
        }
    }

    $h{merge} //= "Y";

    # check required options
    my @required = (
        'abra',       'prinseq', 'genome',         'idxbase',
        'ref_fasta',  'chr',     'amplicon_start', 'amplicon_end',
        'target_bed', 'target_names'
    );

    foreach my $opt (@required) {
        die "Missing required option: $opt\n" if !$h{$opt};
    }

    ## set defaults
    my %defaults = (
        samtools      => 'samtools',
        java          => 'java',
        bwa           => 'bwa',
        bedtools      => 'bedtools',
        rscript       => 'Rscript',
        tmpdir        => '/tmp',
        pysamstats    => 'pysamstats',
        flash         => 'flash',
        min_qual_mean => 30,
        min_len       => 50,
        ns_max_p      => 3,
        wing_length   => 40
    );

    foreach my $opt ( keys %defaults ) {
        $h{$opt} = $defaults{$opt} if !defined $h{$opt};
    }

    $h{high_res} //= 0;

    return %h;
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

sub clean_up {
    foreach my $f ( @_ ) {
        unlink $f;
    }
}
