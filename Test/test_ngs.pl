#!/usr/bin/env perl
use strict;
use lib "../Modules";
use NGS;

my $picard = "/home/wangx112/production/crispr/app/picard-tools-1.107";
my $abra = "/home/wangx112/production/crispr/app/bin/abra-0.94-SNAPSHOT-jar-with-dependencies.jar";
my $bedtools="/home/wangx112/app/bedtools2/bin/bedtools";

my $idxbase="/ng14/ngs/genome/human/hg19/hg19.fa";
my $ref_fasta = "/ng14/ngs/genome/human/hg19/hg19.fa";

my $read1file="test/prefilter/CR1P1A2_R1.fastq.gz";
my $read2file="test/prefilter/CR1P1A2_R2.fastq.gz";
my $amplicon_bed = "/ng14/ngs/illumina/data/P-20160826-0005/test/amplicon.bed";
my $sample="CR1P1A2";
my $outdir="test/align";
my $target_name = 'TGFBR1_CR1';
my $ref_name = 'hg19';
my $chr = 'chr9';
my $target_start = 101900209;
my $target_end = 101900228; 
my $amplicon_start = 101900140; 
my $amplicon_end = 101900651; 
my $base_changes = "101900208C,101900229G,101900232C,101900235A";

my $remove_duplicate = 1;

# realign for large indel detection
my $realign_indel = 1; 

# # require BWA mapping quality score when selecting mapped reads
my $min_mapq = 10;

# # number of bases on each side of sgRNA to see snp
my $guide_flank_length = 50;

my $tmpdir = "/scratch";
my $ngs = new NGS(tmpdir=>$tmpdir, bedtools=>$bedtools, verbose=>1);

my $read1_outfile="$outdir/$sample.R1.fastq.gz";
my $read2_outfile="$outdir/$sample.R2.fastq.gz";
my $singles_outfile="$outdir/$sample.singles.fastq.gz";
my $trim_logfile="$outdir/$sample.trim.log";
my $bamfile = "$outdir/$sample.bam";
my $md_bamfile = "$outdir/$sample.md.bam";
my $readcount = "$outdir/$sample.readcnt";  # to combine into readcount.txt  
my $readchr = "$outdir/$sample.readchr";
my $varstat = "$outdir/$sample.ampvar"; # to use for amplicon-wide plots, snp plots

## For target and indels
my $target_file = "$outdir/$sample.target";
my $target_count = "$outdir/$sample.indel.pct"; # corresponds to previous *summary
my $target_allele = "$outdir/$sample.indel.len"; # corresponds to previous *allele

## HDR stat results
my $hdr_statfile = "$outdir/$target_name/$sample.hdr.stat";
if (0) {
$ngs->trim_reads(read1_inf=>$read1file, 
	read2_inf=>$read2file, 
	read1_outf=>$read1_outfile, 
	read2_outf=>$read2_outfile, 
	singles_outf=>$singles_outfile, 
	trim_logf=>$trim_logfile);

my @bamstats = $ngs->create_bam(sample=>$sample, 
	read1_inf=>$read1_outfile, 
	read2_inf=>$read2_outfile, 
	idxbase=>$idxbase,
	bam_outf=>$bamfile,
	abra=>$abra,
	target_bed=>$amplicon_bed,
	ref_fasta=>$ref_fasta,
	realign_indel=>$realign_indel,
	picard=>$picard,
	mark_duplicate=>1,
	remove_duplicate=>$remove_duplicate
	);

$ngs->readFlow(bamstat_aref=>\@bamstats, 
	r1_fastq_inf=>$read1file, r2_fastq_inf=>$read2file, gz=>1,
	bam_inf=>$bamfile, chr=>$chr, start=>$amplicon_start, end=>$amplicon_end,
	sample=>$sample, outfile=>$readcount);	

$ngs->chromCount($bamfile, $readchr);
# need to use IGV to verify the counts and varstat.

## the bam file has to conform to dedup requirement.
$ngs->variantStat ( bam_inf=>$bamfile, ref_fasta=>$ref_fasta, 
	outfile=>$varstat, chr=>$chr, start=>$amplicon_start, end=>$amplicon_end);
};

$ngs->targetSeq (bam_inf=>$bamfile, min_overlap=>$target_end - $target_start + 1, 
	sample=>$sample, ref_name=>$ref_name, target_name=>$target_name, 
	chr=>$chr, target_start=>$target_start, target_end=>$target_end,
	outfile_detail=>$target_file, 
	outfile_count=>$target_count,
	outfile_allele=>$target_allele);

$ngs->categorizeHDR(bam_inf=>$bamfile, chr=>$chr, 
	base_changes=>$base_changes,
	sample=>$sample,
	min_mapq=>$min_mapq,
	stat_outf=>$hdr_statfile);
