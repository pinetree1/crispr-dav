#!/usr/bin/env perl
## prepare data for alignment view using canvass xpress.
## Author: X. Wang
use strict;
use File::Basename;
use Config::Tiny;
use File::Path qw(make_path);
use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin/Modules";
use Exon;
use Data::Dumper;

my $usage = "Usage: $0 [options] {crispr length distribution file .len} {outfile}
	--ref_fasta <str> Required. Genomic reference fasta file
	--refGene <str> Required. UCSC refGene formatted-file containing transcript/CDS/exon coordinates 
	--geneid <str> Required. Refseq gene name which must exist in the refGene file.
	--samtools <str> Path of samtools. Default: samtools (which is in PATH environment variable)
	--verbose
"; 

my %h;
GetOptions(\%h, 'ref_fasta=s', 'geneid=s', 'refGene=s', 'samtools=s', 'verbose');
die $usage if ( @ARGV != 2 );
die $usage if (!$h{ref_fasta} or ! $h{geneid} or !$h{refGene});

my ($infile, $outfile)= @ARGV;
my $ref_fasta = $h{ref_fasta};
my $refGene = $h{refGene};
my $verbose = $h{verbose};

my $outdir = dirname($outfile);
make_path($outdir) if !-d $outdir;

open(my $ofh, ">$outfile") or die $!;
print $ofh join("\t", "Sample", "Cleavage_Site", "Offset", "Location", "Type",
	"IndelStr", "Indel_Length", "Reads", "Pct", "Strand", "Frame", "Sequence") . "\n";

my ($sample, $site_name, $chr, $guide_start, $guide_end) = getCrisprInfo($infile); 
	
## Get information about the gene coordinates 
my @tmp = refGeneCoord($refGene, $h{geneid});
my $strand = $tmp[2]; # strandness of the gene
my $start = $tmp[5]+1;  # cdsStart
my $end = $tmp[6]; # cdsEnd
my $exonStarts = $tmp[7];
my $exonEnds = $tmp[8];
if ($verbose) {
	print STDERR "$h{geneid}, $strand, cds:$start-$end\n";
	print STDERR "exonStarts: $exonStarts\n";
	print STDERR "exonEnds:   $exonEnds\n";
}

die "Cannot find start or end of $h{geneid}.\n" if (!$start or !$end);
die "Cannot find strand of $h{geneid}.\n" if ($strand ne "+" && $strand ne "-");

my $ex = new Exon(fasta_file=>$ref_fasta, seqid=>$chr, 
	samtools=>$h{samtools}, verbose=>$verbose);

## Full CDS sequence of WT
my ($wt_chr_seq, $wt_chr_coords) = $ex->getExonsSeq(start=>$start-1, end=>$end,
	exonStarts=>$exonStarts, exonEnds=>$exonEnds);

if ( $h{verbose} ) {
	print STDERR "Exons sequence on positive strand:\n$wt_chr_seq\n";
}

my $wt_seq = $strand eq '+' ? $wt_chr_seq : $ex->revcom($wt_chr_seq);

## Guide sequence's segment
my ($guide_segment_str, $guide_cds_seq) = $ex->locateGuideInCDS(strand=>$strand, 
	cdsStart=>$start-1, cdsEnd=>$end, 
	exonStarts=>$exonStarts, exonEnds=>$exonEnds, 
	guide_start=>$guide_start, guide_end=>$guide_end);

my $wt_added = 0;
my $wt_segment = "[1," . length($wt_seq) . "]";

## Segments for alleles
open(my $ifh, $infile) or die $!;
my $line=<$ifh>;
while ($line=<$ifh>) {
	chomp $line;
	my @a = split(/\t/, $line);
	my $indelstr = $a[3];
	my $reads = $a[4];
	my $pct = $a[5];
	my $indel_length = $a[6];
	my $frameshift = $a[7];
		
	my $type = "Wildtype";
	if ( $indelstr =~ /D/ && $indelstr =~ /I/ ) {
		$type = "Complex";
	} elsif ( $indelstr =~ /I/ ) {
		$type="Insertion";
	} elsif ( $indelstr =~ /D/ ) {
		$type="Deletion";
	}
		
	my ($ntseq, $segment);
	if ( $type eq "Wildtype" ) {
		$ntseq=$wt_seq;
		$segment = $wt_segment;
		$wt_added = 1;
	} else {
		print STDERR "\nBegin to process sample: $a[0], reads: $reads, indel: $indelstr\n" if $verbose;
		my $segment_aref;
		($ntseq, $segment_aref) = $ex->getMutantExonsSeq( wt_seq=>$wt_chr_seq, 
			wt_coords=>$wt_chr_coords, indelstr=>$indelstr);
		if ( $strand eq "-" ) {
			$ntseq = $ex->revcom($ntseq);
			$segment_aref = $ex->reverse_segments(segment_aref=>$segment_aref);
		}
		$segment = join(",", @$segment_aref);
		print STDERR "Final result for $indelstr: reads:$reads, segment:$segment\n" if $verbose;
	} 
		
	print $ofh join("\t", $sample, $site_name, $start, $segment, $type, $indelstr, 
		abs($indel_length), $reads, $pct, $strand, 0, $ntseq) . "\n";
}
close $ifh;

if ( !$wt_added ) {
	# add WT entry if not added
	print $ofh join("\t", $sample, $site_name, $start, $wt_segment, "Wildtype", "WT",
		0, 0, 0, $strand, 0, $wt_seq) . "\n"; 
}

## add guide sequence
print $ofh join("\t", $sample, $site_name, $start, $guide_segment_str, "Guide", "", 
		0, 0, 0, $strand, "", $guide_cds_seq)."\n";

close $ofh;

## Return coordinates from UCSC refGene table for a given refseq ID
## refseq ID examples: NM_001005738 
## return an array: (name, chr, strand,  txStart, txEnd,
##  cdsStart, cdsEnd,  exonStarts, exonEnds)
sub refGeneCoord {
	my ($refGene_file, $refseq_id)= @_;
	my $result = qx(awk \'\$2==\"$refseq_id\"\' $refGene_file);
	chomp $result;
	my @a = split(/\t/, $result);
	my @b = ($a[1], $a[2], $a[3], $a[4], $a[5], $a[6], $a[7], $a[9], $a[10]);
	return @b;
}

## Read the length distribution file to return guide information
sub getCrisprInfo { 
	my $file = shift;
	my ($sample, $site_name, $chr, $guide_start, $guide_end);
	open(my $fh, $file) or die $!;
	my $line=<$fh>;
	$line=<$fh>;
	chomp $line;
	my @a = split(/\t/, $line);
	my $sample = $a[0];
	my $site_name = $a[1];
	my ($chr, $guide_start, $guide_end) = split(/[:-]/, $a[2]);
	close $fh;

	return ( $sample, $site_name, $chr, $guide_start, $guide_end);	
}
