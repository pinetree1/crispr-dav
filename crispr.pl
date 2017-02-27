#!/bin/env perl
# Start processing of all samples and integrate them.
# Author: X. Wang

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
crispr_data();

sub process_samples {
    ## process each sample separately
    my @samples = sort keys %{ $h{sample_crisprs} };
	my $total_samples = $#samples + 1;
    my $i = 0;
    foreach my $sample (@samples) {
        $i++;
        next if -f "$h{align_dir}/$sample.done";

		my $fail_flag = "$h{align_dir}/$sample.failed";
		unlink $fail_flag if -f $fail_flag;

        my $cmd = prepareCommand($sample);
        if ( $h{sge} ) {
            my $jobname = Util::getJobName( $sample, "CR", "$i" );
            $cmd = "qsub -cwd -pe orte $h{cores_per_job} -V -o $h{align_dir}/$sample.log -j y -b y -N $jobname $cmd";
            print STDERR "$cmd\n" if $h{verbose};
            if ( system($cmd) != 0 ) {
				die "Failed to submit job for $sample\n";
			}
        } else {
			$cmd .= " >$h{align_dir}/$sample.log 2>&1";
            Util::run($cmd, "Failed in processing sample $sample", $h{verbose}, $fail_flag);
        }
    }

	## wait for jobs to finish
	my $interval = 120; # seconds
	my $max_days = 2;
	my $max_time = $max_days *24*60*60; # seconds
	my $elapsed_time = 0;
	while ( $elapsed_time < $max_time ) {
		my $finished=0;
		foreach my $sample (@samples) {
			if ( -f "$h{align_dir}/$sample.done" ) {
				$finished++;
			} elsif ( -f "$h{align_dir}/$sample.failed" ) {
				die "Failed in processing sample $sample.";
			}
		}
		if ($finished == $total_samples) {
			last;
		} elsif ( $total_samples - $finished <= 2 ) {
			print STDERR "Waiting for " . ($total_samples - $finished) . " sample(s) to finish ...\n";	
		}
		sleep $interval;
		$elapsed_time += $interval;
	}
}

sub crispr_data {
    ## merge crispr-wide data
    my $dir       = $h{align_dir};
    my $hasHeader = 1;
    my @crisprs   = sort keys %{ $h{crispr_samples} };

    foreach my $crispr (@crisprs) {
        my $dest = "$h{deliv_dir}/$crispr/assets";
        make_path($dest);

        # Does this crispr has HDR info?
        my @tmp = split( /,/, $h{crisprs}->{$crispr} );
        my $hdr_bases = $tmp[5];
        print STDERR "hdr_bases:$hdr_bases\n" if $h{verbose};

        my @samp = sort keys %{ $h{crispr_samples}->{$crispr} };
        foreach my $ext ( "cnt", "chr", "snp", "pct", "len", "can", "hdr" ) {
            next if ( $ext eq "can" && !$h{canvasXpress} );

            my $outfile = "$h{align_dir}/$crispr" . "_$ext.txt";
            if ( $ext ne "hdr" or $hdr_bases ) {
                my @infiles;
                if ( $ext eq 'cnt' or $ext eq 'chr' ) {
                    @infiles = map { "$h{align_dir}/$_.$ext" } @samp;
                } else {
                    @infiles = map { "$h{align_dir}/$_.$crispr.$ext" } @samp;
                }

                Util::tabcat( \@infiles, $outfile, $hasHeader );

                my $excel_outfile = "$dest/$crispr" . "_$ext.xlsx";
                Util::tab2xlsx( $outfile, $excel_outfile );
            }

            if ( $ext eq 'cnt' ) {
                my $cmd = "$h{rscript} $Bin/Rscripts/read_stats.R --inf=$outfile --outf=$dest/$crispr.readcnt.png";
                $cmd .= " --rmd=$h{remove_duplicate}";
                Util::run( $cmd, "Failed to create plot of read stats", $h{verbose} );
            } elsif ( $ext eq 'chr' ) {
                my $cmd = "$h{rscript} $Bin/Rscripts/read_chr.R $outfile $dest/$crispr.readchr.png";
                Util::run( $cmd, "Failed to create plot of read count on chromosomes", $h{verbose} );
            } elsif ( $ext eq "pct" ) {
                # create plots for indel count and pct
                my $cmd = "$h{rscript} $Bin/Rscripts/indel.R $outfile $dest/$crispr.indelcnt.png $dest/$crispr.indelpct.png";
                Util::run( $cmd, "Failed to create indel count/pct plots", $h{verbose} );
            } elsif ( $ext eq "hdr" and $hdr_bases ) {
                # create HDR plot
                my $cmd = "$h{rscript} $Bin/Rscripts/hdr_freq.R --inf=$outfile --sub=$crispr --outf=$dest/$crispr.hdr.png";
                Util::run( $cmd, "Failed to create HDR plot", $h{verbose} );
            } elsif ( $ext eq "can" ) {
                # create canvasXpress alignment html file
                foreach my $pct ( 0 .. 1 ) {
                    my $cmd = "$Bin/crispr2cx.pl -input $outfile -perc $pct > $h{deliv_dir}/$crispr/${crispr}_cx$pct.html";
                    Util::run( $cmd, "Failed to create canvasXpress alignment view", $h{verbose} );
                }
            }
        } # ext

        ## move the png files for individual sample to dest
        foreach my $s (@samp) {
            my @pngs = glob("$h{align_dir}/$s.$crispr.*.png");
            next if !@pngs;
            my $str = join( " ", @pngs );
            qx(mv -f $str $dest);
        }

        ## create results html page
        my $cmd = "$Bin/resultPage.pl --ref $h{genome} --gene $h{gene_sym}";
        $cmd .= " --region $h{region} --crispr $h{crispr} --cname $crispr";
        $cmd .= " --nocx" if !$h{canvasXpress};
        $cmd .= " --min_depth $h{min_depth} $h{align_dir} $h{deliv_dir}";
        Util::run( $cmd, "Failed to create results html page", $h{verbose} );
    } # crispr

	print STDERR "All done!\n";
}

sub prepareCommand {
    my $sample = shift;
    my @fastqs = split( /,/, $h{sample_fastqs}{$sample} );
	die "Fastq input is empty for $sample!\n" if !@fastqs;

    my $cmd = "$Bin/sample.pl $sample $fastqs[0] $h{align_dir}";
    $cmd .= " --read2fastq $fastqs[1]" if $fastqs[1];

    $cmd .= " --abra $h{abra} --prinseq $h{prinseq}";
	$cmd .= " --samtools $h{samtools} --bwa $h{bwa} --java $h{java} --bedtools $h{bedtools}";
	$cmd .= " --pysamstats $h{pysamstats} --rscript $h{rscript} --tmpdir $h{tmpdir}";
	$cmd .= " --min_qual_mean $h{min_qual_mean} --min_len $h{min_len}"; 
	$cmd .= " --ns_max_p $h{ns_max_p}";

    $cmd .= " --unique"  if $h{remove_duplicate} eq "Y";
    $cmd .= " --realign" if $h{realign_flag}     eq "Y";
    $cmd .= " --min_mapq $h{min_mapq}" if $h{min_mapq};

    my $crispr_names = join( ",", keys %{ $h{sample_crisprs}->{$sample} } );
    $cmd .= " --genome $h{genome} --idxbase $h{bwa_idx}";
	$cmd .= " --ref_fasta $h{ref_fasta}";
	$cmd .= " --refGene $h{refGene}" if $h{refGene};
    $cmd .= " --geneid $h{geneid}" if $h{geneid};
    $cmd .= " --chr $h{chr} --amplicon_start $h{amplicon_start}"; 
	$cmd .= " --amplicon_end $h{amplicon_end} --target_bed $h{crispr}"; 
	$cmd .= " --target_names $crispr_names --wing_length $h{wing_length}";
	$cmd .= " --min_depth $h{min_depth}";
    $cmd .= " --nocx"    if !$h{canvasXpress};
    $cmd .= " --verbose" if $h{verbose};

    return $cmd;
}

sub get_input {
    my $CONF_TEMPLATE = "$Bin/conf.txt";
    my $usage         = "CRISPR data analysis.

Usage: $0 [options] 

	--conf <str> Configuration file. Required. See template $CONF_TEMPLATE
		It specifies ref_fasta, bwa_idx, min_qual_mean, min_len, etc.

	Specify a reference using --genome or --amp_fasta. Use --genome for standard genomes with fasta file, bwa index, and gene coordinates as specified in configuration file. Use --amp_fasta when trying to use amplicon sequenece as reference. 

	--genome <str> Genome version as specified in configuration file.

	--amp_fasta <str> Amplicon reference fasta file containing a single sequence. 
	--amp_frame <int> Translation starting position in the amplicon reference sequence. If the first codon starts at the first base, then the position is 1. No translation will be performed if the option is omitted. No intron should be present in the amplicon reference sequence if translation is needed. 

	--region <str> Required when --genome option is used. This is a bed file for amplicon region.
		The tab-separated fields are chr, start, end, genesym, refseqid, strand. No header.
		The coordinates are 1-based genomic coordinates. All fields are required.

	--crispr <str> Required. A bed file containing one or multiple CRISPR sgRNA sites. No header.
		Information for each site:
		The tab-separated fields are chr, start, end, crispr_name, sgRNA_sequence, strand, HDR mutations. All fields except HDR mutations are required. 
		The coordinates start and end are 1-based. 
		HDR format: <Pos1><NewBase1>,<Pos2><NewBase2>,... The bases are desired bases on positive strand.
		e.g. 101900208C,101900229G,101900232C,101900235A. No space. 

	--fastqmap <str> Required. A file containing 2 or 3 columns separated by space or tab. No header.
		The tab-separated fields are Samplename, gzipped read1 fastq file, gizpped read2 fastq file (optional).

	--sitemap <str> Required. A file that associates sample name with crispr sites. 
		Each line starts with sample name, followed by crispr sequences. 
		Sample name and crispr sequences are separated by spaces or tabs.

	--sge Submit jobs to SGE default queue. Your system must already have been configured for SGE.

	--outdir <str> Output directory. Default: current directory.
	--help  Print this help message.
	--verbose Print some commands and information.
";

    my @orig_args = @ARGV;

    my %h;
    GetOptions(
        \%h,           'conf=s',   'genome=s',  'amp_fasta=s',
        'amp_frame=i', 'outdir=s', 'help',      'region=s',
        'crispr=s',    'fastqmap=s',  'sitemap=s', 'sge',
        'verbose'
    );

    die $usage if ($h{help} or @orig_args==0);

    foreach my $opt ( "conf", "crispr", "fastqmap", "sitemap" ) {
       	if ( !$h{$opt} ) {
           	die "$usage\n\nMissing --$opt.\n";
       	}
    }

    if ( ( !$h{genome} && !$h{amp_fasta} ) or ( $h{genome} && $h{amp_fasta} ) ) {
       	die "Must specify --genome or --amp_fasta, but not both!\n";
    }

    $h{outdir} //= ".";

    print STDERR "Main command: $0 @orig_args\n" if $h{verbose};

    ## Output directory
    make_path( $h{outdir} );

    ## parameters in the config file
    my $cfg = Config::Tiny->read( $h{conf} );

    ## tools
    foreach my $tool (
        "abra", "prinseq",  "samtools",
        "bwa",    "java", "bedtools", "pysamstats",
        "rscript"
      )
    {
        if ( $cfg->{app}{$tool} ) {
            $h{$tool} = $cfg->{app}{$tool};
        } else {
            die "Could not find $tool info in configuration file!\n";
        }
    }

	if ( $h{sge} ) {
		if ( !(qx(which qsub 2>/dev/null) && qx(env|grep SGE_ROOT)) ) {
			die "SGE was not set up. Could not use --sge option.\n";
		}	
	}

    $h{canvasXpress} = 1;  # whether to create canvasXpress view of sgRNA on cDNA

    if ( $h{genome} ) {
        if ( !$h{region} ) {
            die "--region must be provided together with --genome!\n";
        }

        if ( !$cfg->{ $h{genome} } ) {
            die "Could not find $h{genome} genome section!\n";
        }
        $h{ref_fasta} = $cfg->{ $h{genome} }{ref_fasta};
        $h{bwa_idx}   = $cfg->{ $h{genome} }{bwa_idx};
        $h{refGene}   = $cfg->{ $h{genome} }{refGene};
    } elsif ( $h{amp_fasta} ) {
        $h{ref_fasta} = "$h{outdir}/amplicon.fa";
        $h{bwa_idx}   = $h{ref_fasta};
        $h{region}    = "$h{outdir}/amplicon.bed";

        # copy to $outdir
        qx(cp $h{amp_fasta} $h{ref_fasta}) if ( !-f $h{ref_fasta} );

        # create bwa index
        qx($h{bwa} index $h{ref_fasta});

        my ( $seqid, $len ) = getSeqInfo( $h{ref_fasta} );
		$h{genome} = $seqid;

        # create amplicon bed
        open( my $tmpf, ">$h{region}" ) or die "Could not create $h{region}\n";
        print $tmpf join( "\t", $seqid, 1, $len, $seqid . "_CR", $seqid, "+" )
          . "\n";
        close $tmpf;
		
		$h{canvasXpress} = 0;

        # Create coordinate file for translation
        if ( $h{amp_frame} ) {
        	$h{refGene}   = "$h{outdir}/amplicon.frame";
			$h{geneid}   = $seqid;
            open( my $tmpf, ">$h{refGene}" ) or die $!;
            print $tmpf join( "\t", "#bin",
                "name",       "chrom",    "strand", "txStart",
                "txEnd",      "cdsStart", "cdsEnd", "exonCount",
                "exonStarts", "exonEnds" )
              . "\n";
            print $tmpf join( "\t", "0",
                $seqid, $seqid, "+", $h{amp_frame} - 1,
                $len, $h{amp_frame} - 1,
                $len, 1, $h{amp_frame} - 1, $len )
              . "\n";
            close $tmpf;

			$h{canvasXpress} = 1;
        }
    }

    ## prinseq
    foreach my $p ( "min_qual_mean", "min_len", "ns_max_p" ) {
        $h{$p} = $cfg->{prinseq}{$p};
    }

    # Default for prinseq
    $h{min_qual_mean} //= 30;
    $h{min_len}       //= 50;
    $h{ns_max_p}      //= 3;

    ## Other parameters in the config file
    $h{remove_duplicate} = $cfg->{other}{remove_duplicate};
    $h{realign_flag}     = $cfg->{other}{realign_flag};
    $h{min_mapq}         = $cfg->{other}{min_mapq};
	$h{min_depth}        = $cfg->{other}{min_depth};
    $h{tmpdir}           = $cfg->{other}{tmpdir};
    $h{wing_length}      = $cfg->{other}{wing_length};
	$h{cores_per_job}    = $cfg->{other}{cores_per_job};

    # Defaults:
    $h{remove_duplicate} //= "N";
    $h{realign_flag}     //= "Y";
    $h{min_mapq}         //= 20;
	$h{min_depth}        //= 1000;
    $h{tmpdir}           //= "/tmp";
    $h{wing_length}      //= 40;
	$h{cores_per_job}    //= 2;

    ## Directories
    $h{align_dir} = "$h{outdir}/align";
    $h{deliv_dir} = "$h{outdir}/deliverables";
    make_path( $h{align_dir}, $h{deliv_dir} );

    ## amplicon and crisprs
    my ( $amp, $crisprs, $sample_crisprs, $crispr_samples ) =
      processBeds( $h{region}, $h{crispr}, $h{sitemap} );

    $h{chr}            = $amp->[0];
    $h{amplicon_start} = $amp->[1];
    $h{amplicon_end}   = $amp->[2];
    $h{gene_sym}       = $amp->[3];
    $h{geneid}         = $amp->[4];
    $h{gene_strand}    = $amp->[5];
    $h{crisprs}        = $crisprs;
    $h{sample_crisprs} = $sample_crisprs;
    $h{crispr_samples} = $crispr_samples;

    if ( $h{geneid} eq "" or $h{geneid} eq "N.A." ) {
        $h{canvasXpress} = 0;
    }

    # ***** For --amp_fasta, the canvasXpress part will be different.

    ## fastq files
    $h{sample_fastqs} = getFastqFiles( $h{fastqmap} );
	print Dumper($h{sample_fastqs})."\n" if $h{verbose};

    foreach my $key ( sort keys %h ) {
        print STDERR "$key => $h{$key}\n" if $h{verbose};
    }

	## ensure all samples in sitemap are present in fastqmap
	foreach my $s ( keys %{$h{sample_crisprs}} ) {
		if ( !defined $h{sample_fastqs}{$s} ) {
			die "Error: Sample $s in sitemap is not found in fastqmap!\n"; 
		}
	}
 
    print STDERR "\nCRISPR info:\n" . Dumper( $h{crisprs} ) if $h{verbose};
    print STDERR "\nCRISPR samples:\n" . Dumper( $h{crispr_samples} ) if $h{verbose};
    return %h;
}

sub processBeds {
    my ( $amp_bed, $crispr_bed, $sitemap ) = @_;
	die "Could not find $amp_bed!\n" if !-f $amp_bed;
	die "Could not find $crispr_bed!\n" if !-f $crispr_bed;
	die "Could not find $sitemap!\n" if !-f $sitemap;

    ## amplicon bed
	open(my $ampf, $amp_bed) or die $!;
	my @amp;
	my $cnt=0;
	while (my $line=<$ampf>) {
		next if ( $line =~ /^\#/ or $line !~ /\w/ ); 
		$cnt++;
		if ( $cnt == 1 ) {
			@amp = split( /\t/, $line );
		}
	}			
	close $ampf;
	if ( !@amp ) {
		die "Could not find amplicon information $amp_bed.\n";	
	} else {
		checkBedCoord($amp[1], $amp[2], "Error in $amp_bed");
	}

	if ( $cnt > 1 ) {
		die "Only one amplicon is allowed. No header is allowed.\n";
	} 

    my $MIN_AMP_SIZE=50;
    if ( $amp[2] - $amp[1] < $MIN_AMP_SIZE ) {
        die "Error: Amplicon size too small! Must be at least $MIN_AMP_SIZE bp.\n";
	}

    # ensure each crispr site range is inside amplicon range

    # store crispr info
    my %crisprs;    # name=>chr,start,end,seq,strand,hdr

    open( my $cb, $crispr_bed ) or die "Could not find $crispr_bed.\n";
    my %crispr_names;    # {seq}=>name
    while ( my $line = <$cb> ) {
        next if ( $line !~ /\w/ || $line =~ /^\#/ );
        chomp $line;
        my ( $chr, $start, $end, $name, $seq, $strand, $hdr ) = split( /\t/, $line );
		$seq=uc($seq);

		checkBedCoord($start, $end, "Error in $crispr_bed");

        if ( $chr ne $amp[0] ) {
            die "Error: crispr $name\'s chromosome $chr does not match $amp[0] in amplicon bed.\n";
        }

        if ( $start < $amp[1] || $start > $amp[2] ) {
            die "Error: crispr $name start is not inside amplicon.\n";
        }

        if ( $end < $amp[1] || $end > $amp[2] ) {
            die "Error: crispr $name end is not inside amplicon.\n";
        }

        if ( $crispr_names{$seq} ) {
            die "crispr sequence $seq is duplicated in crispr bed file.\n";
        }

        $crispr_names{$seq} = $name;
        $crisprs{$name} = join( ",", $chr, $start, $end, $seq, $strand, $hdr );
    }
    close $cb;

    ## Find crispr names for each sample
    my %sample_crisprs;    # {sample}{crispr_name}=>1
    my %crispr_samples;    # {crispr_name}{sample}=>1
    my %seen_samples;
    open( my $sm, $sitemap ) or die "Could not find $sitemap\n";
    while ( my $line = <$sm> ) {
        next if ( $line !~ /\w/ or $line =~ /^\#/ );
        chomp $line;
        my @a = split( /\s+/, $line );
        my $sample = shift @a;
        if ( $seen_samples{$sample} ) {
            die "Sample name $sample is duplicated in $sitemap\n";
        }
        $seen_samples{$sample} = 1;

        foreach my $seq (@a) {
			$seq = uc($seq);
            $sample_crisprs{$sample}{ $crispr_names{$seq} } = 1;
            $crispr_samples{ $crispr_names{$seq} }{$sample} = 1;
        }
    }
    close $sm;

    return ( \@amp, \%crisprs, \%sample_crisprs, \%crispr_samples );
}

# return a hash ref of fastq files: {sample}=f1,f2
sub getFastqFiles {
    my $filemap = shift;
    open( my $fh, $filemap ) or die "Could not find $filemap\n";
    my %fastqs;
	my @errors;

    while (my $line=<$fh>) {
        chomp $line;
        my @a      = split (/\s+/, $line);
        my $sample = shift @a;
	
		# ensure fastq files exist
		foreach my $f ( @a ) {
			push (@errors, "$f was not found or empty") if (!-f $f or -z $f); 
			push (@errors, "$f was not .gz file") if $f !~ /\.gz$/;
		}

        if ($sample) {
            $fastqs{$sample} = join( ",", @a );
        }
    }
    close $fh;

	if ( @errors ) {
		die "Fastq file errors: \n" . join("\n", @errors);
	}

    return \%fastqs;
}

# return the ID and length of single sequence in a fasta file
sub getSeqInfo {
    my $fasta = shift;
    open( my $tmpf, $fasta ) or die $!;
    my $seqid;
    my $len = 0;
    while ( my $line = <$tmpf> ) {
        if ( $line =~ />(\S+)/ ) {
            $seqid = $1;
        } else {
            $line =~ s/[^atcgnATCGN]//g;
            $len += length($line);
        }
    }
    close $tmpf;

    die "Error: no sequence ID in $fasta.\n" if !$seqid;
    die "Error: no sequence in $fasta.\n" if !$len;

    return ( $seqid, $len );
}

sub checkBedCoord {
	my ($start, $end, $msg) = @_;

	my @errs;
	if ($start =~ /\D/) {
		push(@errs, "Incorrect Start coordinate: $start.");
	}

	if ($end =~ /\D/) {
		push(@errs, "Incorrect End coordinate: $end.");
	}
	
	if ( $start >= $end ) {
		push(@errs, "Start<=End. But Start must be less than End.");
	}
	
	if (@errs) {
		die "$msg:\n" . join("\n", @errs);
	}
}

