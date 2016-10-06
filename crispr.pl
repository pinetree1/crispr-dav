#!/bin/env perl

#This program analyzes CRSIPR data.
use strict;
use File::Path qw(make_path);
use File::Spec;
use File::Basename;
use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin/Modules";
use Config::Tiny;
use NGS;
use Exon;
use Util;
use Data::Dumper;
$| = 1;

my %h = get_input();
process_samples();
read_flow();
chrom_read();
crispr_data();

sub process_samples { 
	## process each sample separately
	my @samples = sort keys %{$h{sample_crisprs}};
	foreach my $sample ( @samples ) {
		my $cmd = prepareCommand($sample);
		print STDERR "$cmd\n";
		system($cmd);
	}
}

sub read_flow {
	my $dir = $h{align_dir};
	my @samples = sort keys %{$h{sample_crisprs}};
	## merge amplicode-wide read count data
	my $outfile = "$dir/read_count.txt";
	my $hasHeader = 1;
	my @infiles = map { "$dir/$_.cnt" } @samples;
	Util::tabcat(\@infiles, $outfile, $hasHeader);
}

sub chrom_read {
	my $dir = $h{align_dir};
	my @samples = sort keys %{$h{sample_crisprs}};
	## merge amplicode-wide chromosome read count data
	my $outfile = "$dir/chr_read_count.txt";
	my $hasHeader = 1;
	my @infiles = map { "$dir/$_.chr" } @samples;	
	Util::tabcat(\@infiles, $outfile, $hasHeader);
}

sub crispr_data {	
	## merge crispr-wide data  
	my $dir = $h{align_dir};
	my $hasHeader = 1;
	my @crisprs = sort keys %{$h{crispr_samples}};
	foreach my $crispr ( @crisprs ) {
		my @samp = sort keys %{$h{crispr_samples}->{$crispr}};
		foreach my $ext ( "pct", "len", "can", "hdr" ) {
			my $outfile = "$h{align_dir}/$crispr.$ext";
			my @infiles = map { "$h{align_dir}/$_.$crispr.$ext" } @samp;
			Util::tabcat(\@infiles, $outfile, $hasHeader);
		}			
	}
}


sub prepareCommand {
	my $sample = shift;
	my @fastqs = split(/,/, $h{sample_fastqs}{$sample});

	my $cmd = "$Bin/sample.pl $sample $fastqs[0] $h{align_dir}";
	$cmd .= " --read2fastq $fastqs[1]" if $fastqs[1];

	$cmd .= " --picard $h{picard} --abra $h{abra} --prinseq $h{prinseq}"; 
	$cmd .= " --samtools $h{samtools}" if $h{samtools};
	$cmd .= " --bwa $h{bwa}" if $h{bwa}; 
	$cmd .= " --java $h{java}" if $h{java};
	$cmd .= " --bedtools $h{bedtools}" if $h{bedtools};
	$cmd .= " --pysamstats $h{pysamstats}" if $h{pysamstats};
	$cmd .= " --rscript $h{rscript}" if $h{rscript};
	$cmd .= " --tmpdir $h{tmpdir}" if $h{tmpdir};

	$cmd .= " --min_qual_mean $h{min_qual_mean}" if $h{min_qual_mean};
	$cmd .= " --min_len $h{min_len}" if $h{min_len};
	$cmd .= " --ns_max_p $h{bwa}" if $h{bwa};

	$cmd .= " --unique" if $h{remove_duplicate};
	$cmd .= " --realign" if $h{realign_flag};
	$cmd .= " --min_mapq $h{min_mapq}" if $h{min_mapq};

	my $crispr_names = join(",", keys %{$h{sample_crisprs}->{$sample}});
	$cmd .= " --genome $h{genome} --idxbase $h{ref_bwa_idx} --ref_fasta $h{ref_fasta}";	
	$cmd .= " --refGene $h{refGene} --geneid $h{geneid}";
	$cmd .= " --chr $h{chr} --amplicon_start $h{amplicon_start} --amplicon_end $h{amplicon_end}";
	$cmd .= " --target_bed $h{crispr} --target_names $crispr_names";
	$cmd .= " --wing_length $h{wing_length}" if $h{wing_length};
	
	return $cmd;	
}

sub get_input {
	my $DEFAULT_CONF = "$Bin/conf.txt";
	my $DEFAULT_GENOME = "hg19";

	my $usage = "CRISPR data analysis.

Usage: $0 [options] 

	Options:

	--conf <str> Configuration file. Default: $DEFAULT_CONF
		It specifies ref_fasta, ref_bwa_idx, min_qual_mean, min_len, etc.
	--genome <str> Genome version. Default: $DEFAULT_GENOME. Must match config file.
	--outdir <str> Output directory. Default: current directory
	--help  Print this help message.

	Required:

	--region <str> A bed file for amplicon.
		The field values are for chr, start, end, genesym, refseqid, strand. No header.
		The coordinates are 1-based genomic coordinates.

	--crispr <str> A bed file containing one or multiple CRISPR sgRNA sites.
		The field values are for chr, start, end, crispr_name, sgRNA_sequence, strand, HDR mutations. 
		HDR format: <Pos1><NewBase1>,<Pos2><NewBase2>,...
		e.g. 101900208C,101900229G,101900232C,101900235A. No space. Bases must be on positive strand.

	--filemap <str> A file containing 2 or 3 columns separated by space or tab.
		The fields are for Samplename, gzipped read1 fastq file, gizpped read2 fastq file.

	--sitemap <str> Required. A file that associates sample name with crispr sites. 
		Each line starts with sample name, followed by crispr sequences.. 
		Sample name and crispr sequences are separated by spaces or tabs.
";

	my @orig_args = @ARGV;

	my %h;
	GetOptions(\%h, 'conf=s', 'genome=s', 'outdir=s', 'help', 
		'region=s', 'crispr=s', 'filemap=s', 'sitemap=s');

	$h{conf} //= $DEFAULT_CONF;
	$h{genome} //= $DEFAULT_GENOME;
	$h{outdir} //= ".";

	die $usage if $h{help};

	if ( !$h{region} or !$h{crispr} or !$h{filemap} or !$h{sitemap} ) {
		die "$usage\n\nMissing required options.\n";
	}	

	print STDERR "Main command: $0 @orig_args\n";
	
	## Output directory
	make_path($h{outdir});
	
	## parameters in the config file
	my $cfg = Config::Tiny->read($h{conf});
	$h{ref_fasta} = $cfg->{$h{genome}}{ref_fasta};
	$h{ref_bwa_idx} = $cfg->{$h{genome}}{ref_bwa_idx};
	$h{refGene} = $cfg->{$h{genome}}{refGene};
	
	## tools
	foreach my $tool ( "picard",  "abra", "prinseq", 
		"samtools", "bwa", "java", "bedtools", "pysamstats" ) {
		$h{$tool} = $cfg->{app}{$tool} if $cfg->{app}{$tool}; 
	}
	
	## prinseq 
	foreach my $p ("min_qual_mean", "min_len", "ns_max_p") {
		$h{$p} = $cfg->{prinseq}{$p};
	}

	## Other parameters in the config file
	$h{remove_duplicate} = $cfg->{other}{remove_duplicate};
	$h{realign_flag} = $cfg->{other}{realign_flag};
	$h{min_mapq} = $cfg->{other}{min_mapq};
	$h{tmpdir} = $cfg->{other}{tmpdir};
	$h{tmpdir} //= "/tmp";
	$h{wing_length} = $cfg->{other}{wing_length};
	
	## Directories
	$h{align_dir}= "$h{outdir}/align";
	$h{deliv_dir}= "$h{outdir}/deliverables";
	make_path ($h{align_dir}, $h{deliv_dir});
	
	## amplicon and crisprs  
	my ($amp, $crisprs, $sample_crisprs, $crispr_samples)=processBeds($h{region}, 
		$h{crispr}, $h{sitemap});
	$h{chr} = $amp->[0];
	$h{amplicon_start} = $amp->[1];
	$h{amplicon_end} = $amp->[2];
	$h{gene_sym} = $amp->[3];
	$h{geneid} = $amp->[4];
	$h{gene_strand} = $amp->[5];
	$h{crisprs} = $crisprs;
	$h{sample_crisprs} = $sample_crisprs;
	$h{crispr_samples} = $crispr_samples;

	## fastq files
	$h{sample_fastqs} = getFastqFiles($h{filemap});
	
	foreach my $key ( sort keys %h ) {
		print STDERR "$key => $h{$key}\n";
	}

	return %h;
}

sub processBeds {
	my ($amp_bed, $crispr_bed, $sitemap) = @_;

	## amplicon bed
	my $line = qx(cat $amp_bed);
	chomp $line;
	my @amp=split(/\t/, $line);
	
	# ensure each crispr site range is inside amplicon range
	# store crispr info
	my %crisprs; # name=>chr,start,end,seq,strand,hdr

	open(my $cb, $crispr_bed) or die $!;
	my %crispr_names; # {seq}=>name
	while (my $line=<$cb>) {
		next if ( $line !~ /\w/ || $line =~ /^\#/ ); 
		chomp $line;	
		my ($chr, $start, $end, $name, $seq, $strand, $hdr) = split(/\t/, $line);
		if ( $chr ne $amp[0] ) {
			die "Error: crispr $name chr does not match region bed.\n";
		}
 
		if ( $start >= $end ) {
			die "Error: crispr $name start >= end.\n";
		} 
				
		if ($start < $amp[1] || $start > $amp[2]) {
			die "Error: crispr $name start is not inside amplicon.\n";
		}

		if	( $end < $amp[1] || $end > $amp[2] ) {
			die "Error: crispr $name end is not inside amplicon.\n";
		}

		if ( $crispr_names{$seq} ) {
			die "crispr sequence $seq is duplicated in crispr bed file.\n";
		}

		$crispr_names{$seq} = $name;
		$crisprs{$name}=join(",", $chr,$start,$end,$seq,$strand,$hdr);
	}
	close $cb;

	## Find crispr names for each sample
	my %sample_crisprs; # {sample}{crispr_name}=>1
	my %crispr_samples; # {crispr_name}{sample}=>1
	my %seen_samples;
	open(my $sm, $sitemap) or die $!;
	while (my $line=<$sm>) {
		next if ($line !~ /\w/ or $line =~ /^\#/ ); 
		chomp $line;		
		my @a = split(/\s+/, $line);
		my $sample=shift @a;
		if ( $seen_samples{$sample} ) {
			die "Sample name $sample is duplicated in $sitemap\n";
		}
		$seen_samples{$sample}=1;
		
		foreach my $seq ( @a ) {
			$sample_crisprs{$sample}{$crispr_names{$seq}}=1;
			$crispr_samples{$crispr_names{$seq}}{$sample}=1;
		}
	}
	close $sm;

	return (\@amp, \%crisprs, \%sample_crisprs, \%crispr_samples);
}

# return a hash ref of fastq files: {sample}=f1,f2
sub getFastqFiles {
	my $filemap = shift;
	open(my $fh, $filemap) or die $!;
	my %fastqs;
	while (<$fh>) {
		chomp;
		my @a = split /\t/;
		my $sample = shift @a;
		if ( $sample ) {
			$fastqs{$sample} = join(",", @a);
		}
	}
	close $fh;
	return \%fastqs;
}
