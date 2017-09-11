#!/usr/bin/env perl
# Start processing of all samples and integrate them.
# Author: X. Wang

use 5.010;
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
my $failed_href=process_samples();
crispr_data($failed_href);

sub process_samples {

    # Save a copy of the description of intermediate files
    if ( -f "$Bin/interm_file_desc" ) {
        qx(cp $Bin/interm_file_desc $h{align_dir}/README);
    }

    ## process each sample separately
    my @samples       = sort keys %{ $h{sample_crisprs} };
    my $total_samples = $#samples + 1;
    my $i             = 0;

    my %jobnames;
    foreach my $sample (@samples) {
        $i++;
        next if -f "$h{align_dir}/$sample.done";

        my $fail_flag = "$h{align_dir}/$sample.failed";
        unlink $fail_flag if -f $fail_flag;

        my $cmd = prepare_command($sample);
        print STDERR "\nProcessing $sample ...\n";
        if ( $h{sge} ) {
            my $jobname = Util::getJobName( "C", "$i" );
            my $cores_per_job = 2;

            # set this to at least 2 so as not to overwhelm the 
            # system when there are too many samples.
            $cmd = "qsub -cwd -pe orte $cores_per_job -V -o $h{align_dir}/$sample.log" . 
                " -j y -b y -N $jobname $cmd";
            print STDERR "$cmd\n" if $h{verbose};
            if ( system($cmd) ) {
                die "Failed to submit job for $sample\n";
            }
            $jobnames{$jobname} = $sample;
        }
        else {
            $cmd .= " >$h{align_dir}/$sample.log 2>&1";
            Util::run( $cmd, "", $h{verbose}, $fail_flag, 1 );
        }
    }

    ## Wait for jobs to finish.  
    my $interval     = 120;                         # seconds
    my $max_days     = 1;
    my $max_time     = $max_days * 24 * 60 * 60;    # seconds
    my $elapsed_time = 0;
    my @failures;  # failed samples
    while ( $elapsed_time < $max_time ) {
        sleep $interval;
        $elapsed_time += $interval;
        my $success = 0;
        @failures = ();
        foreach my $sample (@samples) {
            if ( -f "$h{align_dir}/$sample.done" ) {
                $success++;
            }
            elsif ( -f "$h{align_dir}/$sample.failed" ) {
                push( @failures, $sample );
            }
        }

        my $finished = $success + scalar(@failures);
        if ( $finished == $total_samples ) {
            last;
        }
    }

    if (@failures ) {
        print STDERR "\nErrors in processing samples:\n";
        foreach my $s ( @failures ) {
            my $err;
            if ( -s "$h{align_dir}/$s.failed" ) {
                open(my $erf, "$h{align_dir}/$s.failed");
               	$err= <$erf>; chomp $err;
                close $erf;
            }

            print STDERR "\t" . join(": ", $s, $err) . "\n";
        }
        print STDERR "\n\tPlease check log files in $h{align_dir}.\n";
        exit 1 if scalar(@failures)==$total_samples; 
    }

    my %failed_samples = map{ $_ => 1 } @failures;
    return \%failed_samples;
}

sub crispr_data {
    ## merge crispr-wide data
  	my $failed_samples = shift; # hash ref 
    my $dir       = $h{align_dir};
    my $hasHeader = 1;
    my @crisprs   = sort keys %{ $h{crispr_samples} };
    my $plot_ext  = $h{high_res} ? "tif" : "png";

    foreach my $crispr (@crisprs) {
        print STDERR "\nMerging data and creating plots for $crispr.\n";
        my $dest = "$h{deliv_dir}/$crispr/Assets";
        make_path($dest);

        # Does this crispr has HDR info?
        my @tmp = split( /,/, $h{crisprs}->{$crispr} );
        my $hdr_bases = $tmp[5];

        # combine results of all successful samples
        my @samp;  
        foreach my $s ( sort keys %{ $h{crispr_samples}->{$crispr} } ) {
            push (@samp, $s) if !$failed_samples->{$s};
        }

        foreach my $ext ( "cnt", "chr", "snp", "pct", "len", "can", "hdr", "hdr.snp" ) {
            next if ( $ext eq "can" && !$h{canvasXpress} );
            next if ( ($ext eq "hdr" or $ext eq "hrd.snp")  && !$hdr_bases );

            my $outfile = "$h{align_dir}/$crispr" . "_$ext.txt";
            my (@infiles, $f);
            foreach my $s ( @samp ) {
                if ( $ext eq 'cnt' or $ext eq 'chr' ) {
                    $f = "$h{align_dir}/$s.$ext";
                } else {
                    $f = "$h{align_dir}/$s.$crispr.$ext";
                }
                push(@infiles, $f) if -f $f;
            }

            if ( @infiles ) {
                Util::tabcat( \@infiles, $outfile, $hasHeader );
                Util::tab2xlsx( $outfile, "$dest/${crispr}_$ext.xlsx" );
            }
        }
       
        # plot reads vs stages 
        my $infile = "$h{align_dir}/$crispr" . "_cnt.txt";
        my $cmd = "$h{rscript} $Bin/Rscripts/read_stats.R --inf=$infile" .
            " --outf=$dest/$crispr.readcnt.$plot_ext --rmd=$h{remove_duplicate}"; 
        $cmd .= " --high_res=$h{high_res}" if $h{high_res};
        Util::run($cmd, "Failed to create plot of read stats", $h{verbose});
        
        # plot reads vs chromosomes 
        $infile="$h{align_dir}/$crispr" . "_chr.txt";
        $cmd = "$h{rscript} $Bin/Rscripts/read_chr.R --inf=$infile" .
               " --outf=$dest/$crispr.readchr.$plot_ext";
        $cmd .= " --high_res=$h{high_res}" if $h{high_res};
        Util::run( $cmd,
                    "Failed to plot read count on chromosomes",
                    $h{verbose});

        # plot indel count and pct
        $infile="$h{align_dir}/$crispr" . "_pct.txt";
        $cmd = "$h{rscript} $Bin/Rscripts/indel.R --inf=$infile" .
               " --cntf=$dest/$crispr.indelcnt.$plot_ext" .
               " --pctf=$dest/$crispr.indelpct.$plot_ext";
        $cmd .= " --high_res=$h{high_res}" if $h{high_res};
        Util::run( $cmd, "Failed to plot indel count/pct", $h{verbose});
            
        # plot HDR 
        if ( $hdr_bases ) {
            $infile="$h{align_dir}/$crispr" . "_hdr.txt";
            $cmd = "$h{rscript} $Bin/Rscripts/hdr.R --inf=$infile --sub=$crispr" .
                   " --outf=$dest/$crispr.hdr.$plot_ext";
            $cmd .= " --high_res=$h{high_res}" if $h{high_res};
            Util::run( $cmd, "Failed to create HDR plot", $h{verbose});
        }

        # generate data for interactive alignment view
        $infile="$h{align_dir}/$crispr" . "_can.txt";
        foreach my $pct ( 0 .. 1 ) {
            $cmd = "$Bin/crispr2cx.pl -input $infile -perc $pct >" .
                   " $h{deliv_dir}/$crispr/${crispr}_cx$pct.html";
            Util::run( $cmd, "Failed to create canvasXpress alignment view",
                        $h{verbose});
        }

        ## move the image files for individual sample to dest
        foreach my $s (@samp) {
            my @plots = glob("$h{align_dir}/$s.$crispr.*.$plot_ext");
            next if !@plots;
            my $str = join( " ", @plots );
            qx(mv -f $str $dest);
        }

        ## create results html page
        my $cmd = "$Bin/report.pl --ref $h{genome} --gene $h{gene_sym}" .
            " --region $h{region} --crispr $h{crispr} --cname $crispr" .
            " --min_qual_mean $h{min_qual_mean} --min_len $h{min_len}" .
            " --ns_max_p $h{ns_max_p} --min_mapq $h{min_mapq}" .
            " --wing_length $h{wing_length}";
        $cmd .= " --nocx" if !$h{canvasXpress};
        $cmd .= " --high_res" if $h{high_res};
        $cmd .= " --realign" if $h{realign_flag} eq "Y";
        $cmd .= " $h{align_dir} $h{deliv_dir}";
        Util::run( $cmd, "Failed to create results html page", 
              $h{verbose});
        print STDERR "Generated HTML report for $crispr.\n";
    } # for each crispr
}

sub prepare_command {
    my $sample = shift;
    my @fastqs = split( /,/, $h{sample_fastqs}{$sample} );
    die "Fastq input is empty for $sample!\n" if !@fastqs;

    my $cmd = "$Bin/sample.pl $sample $fastqs[0] $h{align_dir}";
    $cmd .= " --read2fastq $fastqs[1]" if $fastqs[1];
    $cmd .= " --picard $h{picard}"     if $h{picard};
    $cmd .= " --abra $h{abra} --prinseq $h{prinseq}" .
       " --samtools $h{samtools}" . 
       " --java $h{java} --bedtools $h{bedtools}" . 
       " --pysamstats $h{pysamstats} --rscript $h{rscript}" . 
       " --tmpdir $h{tmpdir} --min_qual_mean $h{min_qual_mean}" .
       " --min_len $h{min_len} --ns_max_p $h{ns_max_p}";

    $cmd .= " --unique"  if $h{remove_duplicate} eq "Y";
    $cmd .= " --realign" if $h{realign_flag}     eq "Y";
    $cmd .= " --min_mapq $h{min_mapq}" if $h{min_mapq};

    my $crispr_names = join( ",", keys %{ $h{sample_crisprs}->{$sample} } );
    $cmd .= " --genome $h{genome} --idxbase $h{bwa_idx}";
    $cmd .= " --ref_fasta $h{ref_fasta}";
    $cmd .= " --refGene $h{refGene}" if $h{refGene};
    $cmd .= " --refseqid $h{refseqid}" if $h{refseqid};
    $cmd .= " --chr $h{chr} --amplicon_start $h{amplicon_start}" .
       " --amplicon_end $h{amplicon_end} --target_bed $h{crispr}" .
       " --target_names $crispr_names --wing_length $h{wing_length}";
    $cmd .= " --nocx" if !$h{canvasXpress};
    $cmd .= " --high_res" if $h{high_res};
    $cmd .= " --verbose" if $h{verbose};

    return $cmd;
}

sub get_input {
    my $CONF_TEMPLATE = "$Bin/conf.txt";
    my $usage         = "CRISPR data analysis and visualization pipeline.

Usage: $0 [options] 

    --conf <str> Configuration file. Required. See template $CONF_TEMPLATE
        It has information about genome locations, tools, and parameters.  

    Specify a reference using --genome or --amp_fasta, but not both. 
    Use --genome for standard genome, such as hg19. Need to have paths of fasta file, 
    bwa index, and refGene coordinate file in the configuration file. To download the  
    coordinate file, go to UCSC Genome Browser, in TableBrowser, select group:Genes 
    and Gene Predictions, track:RefSeq Genes, table:refGene, region:genome,
    output format:all fields from selected table. The downloaded tab-delimited file 
    should have these columns:
    bin,name,chrom,strand,txStart,txEnd,cdsStart,cdsEnd,exonStarts,exonEnds,... 
    Use --amp_fasta when using a custom amplicon sequenece as reference. 

    --genome <str> Genome version (e.g. hg19) as specified in configuration file.

    --amp_fasta <str> Amplicon reference fasta file containing a single sequence. 
    --codon_start <int> Translation starting position in the amplicon reference sequence. 
        If the first codon starts at the first base, then the position is 1. No translation 
        will be performed if the option is omitted. No intron should be present in the 
        amplicon reference sequence if translation is needed. 

    --region <str> Required when --genome option is used. This is a bed file for amplicon region.
        The tab-separated fields are chr, start, end, genesym, refseqid, strand(+/-). 
        No header. All fields are required.
        The start and end are 0-based; start is inclusive and end is exclusive.
        Genesym is gene symbol. Refseqid is used to identify transcript coordinates in 
        UCSC refGene coordinate file. If refseqid is '-', no alignment view will be created. 
        Only one row is allowed this file. If an experiment has two amplicons, run the 
        pipeline separately for each amplicon. 

    --crispr <str> Required. A bed file containing one or more CRISPR sgRNA sites.
        Tab-delimited file. No header. Information for each site:
        The fields are: chr, start, end, CRISPR_name, sgRNA_sequence, strand, and 
        HDR mutations.  All fields except HDR mutations are required. The start and end 
        are 0-based; start is inclusive and end is exclusive. CRISPR names and sequences 
        must be unique. 
        HDR format: <Pos1><NewBase1>,<Pos2><NewBase2>,... The bases are desired new bases 
        on positive strand,e.g.101900208C,101900229G,101900232C,101900235A. No space. The 
        positions are 1-based and inclusive. 

    --fastqmap <str> Required. A tab-delimited file containing 2 or 3 columns. No header.
        The fields are sample name, read1 fastq file, and optionally read2 fastq file.
        Fastq files must be gizpped and and file names end with .gz.

    --sitemap <str> Required. A tab-delimited file that associates sample name with CRISPR 
        sites. No header. Each line starts with sample name, followed by one or more sgRNA
        guide sequences. This file controls what samples to be analyzed. 

    --sge Submit jobs to SGE queue. The system must already have been configured for SGE.
    --outdir <str> Output directory. Default: current directory.
    --help  Print this help message.
    --verbose Print some commands and information for debugging.
";

    my @all_args = @ARGV;

    my %h;
    GetOptions(
        \%h,           'conf=s',     'genome=s',  'amp_fasta=s',
        'codon_start=i', 'outdir=s',   'help',      'region=s',
        'crispr=s',    'fastqmap=s', 'sitemap=s', 'sge',
        'verbose'
    ) or exit;

    die $usage if ( $h{help} or @all_args == 0 );

    foreach my $opt ( "conf", "crispr", "fastqmap", "sitemap" ) {
        if ( !$h{$opt} ) {
            die "$usage\n\nMissing --$opt.\n";
        }
    }

    if ( !-f $h{conf} ) {
        die "Error: Could not find $h{conf}.\n"; 
    }

    if ( ( !$h{genome} && !$h{amp_fasta} ) or ( $h{genome} && $h{amp_fasta} ) )
    {
        die "Must specify either --genome or --amp_fasta\n";
    } 

    $h{pid} = $$;

    $h{outdir} //= ".";

    print STDERR "Main command: $0 @all_args\n" if $h{verbose};

    ## Output directory
    make_path($h{outdir}, {error=>\my $err});
    die "Could not create directory $h{outdir}\n" if @$err;

    ## parameters in the config file
    my $cfg = Config::Tiny->read( $h{conf} );

    ## sections
    for my $s ( "app", "other" ) {
        die "Error: section [$s] is missing in $h{conf}.\n" if !$cfg->{$s};
    }
    
    # app section
    foreach my $tool (
        "abra", "prinseq",  "samtools", 
        "java", "bedtools", "pysamstats", "rscript"
      )
    {
        if ( !$cfg->{app}{$tool} ) {
            if ( $tool eq "abra" or $tool eq "prinseq" ) {
                die "Could not find $tool under section [app] in $h{conf}!\n";
            } else {
                # assuming using default.
                if ( $tool eq "rscript" ) {
                    $cfg->{app}{$tool} = "Rscript";
                } else {
                    $cfg->{app}{$tool} = $tool;
                }

                #if ( system("which $cfg->{app}{$tool} > /dev/null") ) {
                $cfg->{app}{$tool}=qx(which $cfg->{app}{$tool}) or 
                    die "$tool must either be specified under [app]" .  
                        " in $h{conf} or accessible in your PATH\n"; 
                chomp($cfg->{app}{$tool}); 
            }
        } 

        if ( $cfg->{app}{$tool} =~ /\// && !-f $cfg->{app}{$tool} ) {
            die "Could not find $cfg->{app}{$tool}!\n";
        }

        $h{$tool} = $cfg->{app}{$tool};
        if ( $tool ne "abra" ) {
            if ( $h{$tool} =~ /\// && ! -x $h{$tool} ) {
                die "Error: $h{$tool} is not executable. Run: chmod +x $h{$tool}\n"; 
            }
        }
    }
    
    # Ensure bwa is in PATH
    my $bwa= qx(which bwa 2>/dev/null) or 
        die "Error: bwa not found. It must be in your PATH\n";
    chomp $bwa;
    $h{bwa} = $bwa;

    check_pysam( $h{pysamstats} );
    check_perlmod();
    if ( $cfg->{app}{picard} ) {
        $h{picard} = $cfg->{app}{picard};
    }

    if ( $h{sge} ) {
        if ( !( qx(which qsub 2>/dev/null) && qx(env|grep SGE_ROOT) ) ) {
            die "SGE was not set up. Could not use --sge option.\n";
        }
    }

    ## Directories
    $h{align_dir} = "$h{outdir}/align";
    $h{deliv_dir} = "$h{outdir}/deliverables";
    $h{tmpdir}    = "$h{align_dir}/tmp";
    make_path( $h{align_dir}, $h{deliv_dir}, $h{tmpdir} );

	check_rpkg($h{rscript}, $h{outdir});

    if ( $h{genome} ) {
        $h{genome} =~ s/\s//g;
        if ( !$h{region} ) {
            die "--region must be provided together with --genome!\n";
        }

        if ( !$cfg->{ $h{genome} } ) {
            die "Could not find [$h{genome}] section in configuration file!\n";
        }
        $h{ref_fasta} = $cfg->{ $h{genome} }{ref_fasta};
        $h{bwa_idx}   = $cfg->{ $h{genome} }{bwa_idx};
        $h{refGene}   = $cfg->{ $h{genome} }{refGene};

        foreach my $name ( "ref_fasta", "bwa_idx" ) {
            if ( !$h{$name} ) { 
                die "Could not find $name under [$h{genome}] in $h{conf}\n";
            }
        }

        if ( !-f $h{ref_fasta} ) {
            die "Could not find $h{ref_fasta}\n";
        }

        if ( !-f "$h{bwa_idx}.bwt" ) {
            die "Could not find bwa index files, e.g. $h{bwa_idx}.bwt\n"; 
        }

        if ( $h{refGene} && !-f $h{refGene} ) {
            die "Could not find refGene file $h{refGene}!\n" . 
                "  refGene is optional under [$h{genome}] in $h{conf}.\n" . 
                "  It's needed for creating alignment view.\n";
        }
    }
    elsif ( $h{amp_fasta} ) {
        if ( defined $h{codon_start} ) {
            if ( $h{codon_start} < 1 ) {
               die "codon_start is $h{codon_start}, but it must be at least 1.\n";
           	} 
        }

        $h{ref_fasta} = "$h{align_dir}/" . basename($h{amp_fasta});
        my ($seqid, $len)= process_custom_seq($h{amp_fasta}, "$h{ref_fasta}");
        $h{bwa_idx}   = $h{ref_fasta};
        $h{region}    = "$h{align_dir}/amplicon.bed";

        # copy to $outdir
        qx(cp $h{amp_fasta} $h{ref_fasta}) if ( !-f $h{ref_fasta} );

        # create bwa index
        qx($h{bwa} index $h{ref_fasta} 2>/dev/null);

        $h{genome} = $seqid;

        # create amplicon bed
        open( my $tmpf, ">$h{region}" ) or die "Could not create $h{region}\n";
        print $tmpf join( "\t", $seqid, 0, $len, $seqid, $seqid, "+" ) . "\n";
        close $tmpf;

        # Create coordinate file for translation
        if ( $h{codon_start} ) {
            $h{refGene} = "$h{align_dir}/amplicon.frame";
            $h{refseqid}  = $seqid;
            open( my $tmpf, ">$h{refGene}" ) or die $!;
            print $tmpf join( "\t",
                "#bin",      "name",       "chrom",    "strand",
                "txStart",   "txEnd",      "cdsStart", "cdsEnd",
                "exonCount", "exonStarts", "exonEnds" ) . "\n";
            print $tmpf join( "\t",
                "0", $seqid, $seqid, "+", 
                $h{codon_start} - 1, $len, $h{codon_start} - 1, $len, 
                1, $h{codon_start} - 1, $len ) . "\n";
            close $tmpf;
        }
    }

    ## Make sure ref_fasta's directory is writable for pysamstats 
    ## or samtools faidx to create FASTA index if not present.
    if ( ! -w dirname($h{ref_fasta}) ) {
        die "Error: $h{ref_fasta}\'s directory is not writable.\n";
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
    $h{wing_length}      = $cfg->{other}{wing_length};
    $h{high_res}         = $cfg->{other}{high_res};

    # Defaults:
    $h{remove_duplicate} ||= "N";
    $h{realign_flag}     ||= "Y";
    check_yn($h{remove_duplicate}, 
      "remove_duplicate value ($h{remove_duplicate}) must be Y or N(default)");
    check_yn($h{realign_flag}, 
      "realign_flag ($h{realign_flag}) must be Y(default) or N");
    $h{min_mapq}         //= 20;
    $h{wing_length}      //= 40;
    $h{high_res}         //= 0;

    ## Directories
    $h{align_dir} = "$h{outdir}/align";
    $h{deliv_dir} = "$h{outdir}/deliverables";
    $h{tmpdir}    = "$h{outdir}/align/tmp";
    make_path( $h{align_dir}, $h{deliv_dir}, $h{tmpdir} );

    ## amplicon and crisprs
    my ( $amp, $crisprs, $sample_crisprs, $crispr_samples ) =
      process_beds( $h{region}, $h{crispr}, $h{sitemap} );

    $h{chr}            = $amp->[0];
    $h{amplicon_start} = $amp->[1] + 1;
    $h{amplicon_end}   = $amp->[2];
    $h{gene_sym}       = $amp->[3];
    $h{refseqid}       = $amp->[4];
    $h{gene_strand}    = $amp->[5];

    $h{crisprs}        = $crisprs;
    $h{sample_crisprs} = $sample_crisprs;
    $h{crispr_samples} = $crispr_samples;

    # whether to create canvasXpress view on cDNA
    if ( $h{refseqid} 
        && $h{refseqid} ne "-" 
        && -f $h{refGene}
        && Util::refGeneCoord($h{refGene}, $h{refseqid})
    ) {
        $h{canvasXpress} = 1;
    } else {
        $h{canvasXpress} = 0;
    }

    ## fastq files
    $h{sample_fastqs} = get_fastq_files( $h{fastqmap} );
    print Dumper( $h{sample_fastqs} ) . "\n" if $h{verbose};

    ## ensure all samples in sitemap are present in fastqmap
    foreach my $s ( keys %{ $h{sample_crisprs} } ) {
        if ( !defined $h{sample_fastqs}{$s} ) {
            die "Error: Sample $s in $h{sitemap} is not found in $h{fastqmap}!\n";
        }
    }

    foreach my $key ( sort keys %h ) {
        print STDERR "$key => $h{$key}\n" if $h{verbose};
    }
    if ( $h{verbose} ) {
        print STDERR "\nCRISPR info:\n" . Dumper($h{crisprs});
        print STDERR "\nCRISPR samples:\n" . Dumper($h{crispr_samples});
    }

    return %h;
}

sub check_yn {
    my ($value, $errmsg) = @_;
    die "$errmsg\n" if ($value ne "Y" && $value ne "N");
}

sub process_beds {
    my ( $amp_bed, $crispr_bed, $sitemap ) = @_;
    die "Could not find $amp_bed!\n"    if !-f $amp_bed;
    die "Could not find $crispr_bed!\n" if !-f $crispr_bed;
    die "Could not find $sitemap!\n"    if !-f $sitemap;

    ## amplicon bed
    open( my $ampf, $amp_bed ) or die $!;
    my @amp;
    my $cnt = 0;
    while ( my $line = <$ampf> ) {
        next if ( $line =~ /^#/ or $line !~ /\w/ );
        chomp $line;
        $line =~ s/ //g;
        $cnt++;
        if ( $cnt == 1 ) {
            @amp = split( /\t/, $line );
        }
    }
    close $ampf;
    if ( !@amp ) {
        die "Could not find amplicon information $amp_bed.\n";
    }
    elsif ( @amp < 6 ) {
        die "Error: $amp_bed does not have 6 columns.\n";
    }
    else {
        check_bed_coord( $amp[1], $amp[2], "Error in $amp_bed" );
    }

    if ( $cnt > 1 ) {
        die "Only one amplicon is allowed. No header is allowed.\n";
    }

    $amp[5] = uc( $amp[5] );
    die "Strand must be + or - in bed file!\n" if $amp[5] !~ /[+-]/;

    my $MIN_AMP_SIZE = 50;
    if ( $amp[2] - $amp[1] < $MIN_AMP_SIZE ) {
        die "Error: Amplicon size too small!" . 
            " Must be at least $MIN_AMP_SIZE bp.\n";
    }

    # ensure each crispr site range is inside amplicon range

    # store crispr info
    my %crisprs;    # name=>chr,start,end,seq,strand,hdr

    open( my $cb, $crispr_bed ) or die "Could not find $crispr_bed.\n";
    my %crispr_names;    # {seq}=>name. Ensure unique CRISPR sequences
    my %seen_names; # to ensure unique CRISPR names 
    while ( my $line = <$cb> ) {
        next if ( $line !~ /\w/ || $line =~ /^#/ );
        $line =~ s/ //g;
        chomp $line;
        my @a = split(/\t/, $line);
        die "Error: In $crispr_bed, This entry does not have at least " .  
           "6 tab-separated columns:\n$line\n" if scalar(@a) < 6;  

        my ($chr, $start, $end, $name, $seq, $strand, $hdr) = @a;
        die "Strand must be + or - in bed file!\n" if $strand !~ /[+-]/;
        $seq = uc($seq);
        $seq =~ s/U/T/g;

        check_bed_coord( $start, $end, "Error in $crispr_bed" );

        if ( $chr ne $amp[0] ) {
            die "Error: CRISPR $name\'s chromosome $chr does not" . 
                " match $amp[0] in amplicon bed.\n";
        }

        if ( $start < $amp[1] || $start > $amp[2] ) {
            die "Error: CRISPR $name start is not inside amplicon.\n";
        }

        if ( $end < $amp[1] || $end > $amp[2] ) {
            die "Error: CRISPR $name end is not inside amplicon.\n";
        }

        if ( $crispr_names{$seq} ) {
            die "Error: CRISPR sequence $seq is duplicated in $crispr_bed.\n";
        }

        if ( $seen_names{$name} ) {
             die "Error: CRISPR name $name is duplicated in $crispr_bed.\n";
        }
        $crispr_names{$seq} = $name;
        $seen_names{$name} = 1;
        $crisprs{$name} = join( ",", $chr, $start, $end, $seq, $strand, $hdr );
    }
    close $cb;

    ## Find crispr names for each sample
    my %sample_crisprs;    # {sample}{crispr_name}=>1
    my %crispr_samples;    # {crispr_name}{sample}=>1
    open( my $sm, $sitemap ) or die "Could not find $sitemap\n";
    my %dup; # avoid duplicated entry of sample and seq combination
    while ( my $line = <$sm> ) {
        next if ( $line !~ /\w/ or $line =~ /^\#/ );
        chomp $line;
        my @a = split( /\t/, $line );
        if (@a < 2) {
            die "In $sitemap, each line must have at least 2 tab-separated\n" . 
                " columns:\nError line: $line\n";
        }

        # remove space in each element
        for (my $i=0; $i<@a; $i++) {
            $a[$i] =~ s/ //g;
        }

        my $sample = shift @a;
        next if !$sample;

        my $found_seq = 0;
        foreach my $seq (@a) {
            next if !$seq;
            $seq = uc($seq);
            die "Sequence $seq contained non-ACGT letter!\n" if $seq !~ /[ACGT]/;
            die "Error: $seq in $sitemap is not in $crispr_bed!\n" if !$crispr_names{$seq};
            $found_seq  = 1;

            if ( $dup{$sample}{$seq} ) {
                 die "Error: $sample and $seq combination is duplicated.\n";
            }
            $dup{$sample}{$seq} = 1;
            $sample_crisprs{$sample}{ $crispr_names{$seq} } = 1;
            $crispr_samples{ $crispr_names{$seq} }{$sample} = 1;
        }
        die "No CRISPR sequence in $line!\n" if !$found_seq;
    }
    close $sm;

    return ( \@amp, \%crisprs, \%sample_crisprs, \%crispr_samples );
}

# return a hash ref of fastq files: {sample}=f1,f2
sub get_fastq_files {
    my $filemap = shift;
    open( my $fh, $filemap ) or die "Could not find $filemap\n";
    my %fastqs;
    my (%seen, %errors);
    while ( my $line = <$fh> ) {
        next if ( $line =~ /^#/ or $line !~ /\w/ );
        chomp $line;
        my @a = split( /\t/, $line );
        if ( scalar(@a) < 2 or scalar(@a) > 3 ) {
            die "In $filemap, a sample can have only 1 or 2 fastq" . 
               " files separated by tab.\n" . 
               "Error line: $line\n"; 
        }

        my $sample = shift @a;
        $sample =~ s/ //g;
        next if !$sample;

        my @b;

        # ensure fastq files exist
        foreach my $f (@a) {
            next if !$f;
            push ( @{$errors{$f}}, "File not found") if !-f $f; 
            push ( @{$errors{$f}}, "File not .gz") if $f !~ /\.gz$/ ;
            push ( @{$errors{$f}}, "File duplicated") if $seen{$f};
            push( @b, $f ) if !$errors{$f};
            $seen{$f} = 1;
        }

        if (@b) {
            $fastqs{$sample} = join( ",", @b );
        }
    }
    close $fh;

    if ( %errors ) {
        print STDERR "Fastq file errors:\n";
        foreach my $f ( sort keys %errors ) {
            print STDERR "$f: " . join("; ", @{$errors{$f}}) . "\n";
        } 
        exit 1;
    }

    return \%fastqs;
}

sub check_bed_coord {
    my ( $start, $end, $msg ) = @_;

    my @errs;
    if ( $start =~ /\D/ ) {
        push( @errs, "Incorrect Start coordinate: $start." );
    }

    if ( $end =~ /\D/ ) {
        push( @errs, "Incorrect End coordinate: $end." );
    }

    if ( $start >= $end ) {
        push( @errs, "Start<=End. But Start must be less than End." );
    }

    if (@errs) {
        die "$msg:\n" . join( "\n", @errs ) . "\n";
    }
}

sub check_pysam {
    my $pysamstats = shift;
    if ( system("$pysamstats --help > /dev/null") ) {
        my $msg = "$pysamstats did not run properly. If there is error";
		$msg .= " importing a module, please include the module path in";
        $msg .= " environment variable PYTHONPATH.";
        die "$msg\n";
    }
}

sub check_perlmod {
    my @mods = qw(Config::Tiny
      Excel::Writer::XLSX
      JSON
    );

    foreach my $mod (@mods) {
        eval("use $mod");
        die "Cannot find $mod!\n" if $@;
    }
}

sub check_rpkg {
    my ($rscript_path, $tmpdir)=@_;
    my $script = "$tmpdir/.check.R";
    open(my $tmpf, ">$script") or die "could not create $script\n";
    print $tmpf "library(ggplot2)\nlibrary(naturalsort)\n" . 
        "library(reshape2)\n";
    close $tmpf;
    if ( system("$rscript_path $script") ) {
        die "Error: Missing required R package.\n"; 
    }
    unlink $script;
}

sub stop_processing {
    my $href = shift;

    my $queue_jobs = Util::getJobCount($href);
    return if $queue_jobs;

    my $delay = 300;
    sleep $delay;

    my $log_cnt  = 0;
    my %jobnames = %{$href};
    my $job_cnt = 0;
    while ( my ( $j, $s ) = each %jobnames ) {
		$job_cnt ++;
        if ( -f "$h{align_dir}/$s.log" ) {
            $log_cnt++;
        }
    }

    my @done   = glob("$h{align_dir}/*.done");
    my @failed = glob("$h{align_dir}/*.failed");
    if ( $log_cnt == $job_cnt && !@done && !@failed ) {
        print STDERR "Queued jobs have failed. Progam exited.\n";
        system("kill $h{pid}");
        exit 1;
    }
}

# Ensure custom seq in fasta format with one sequence only, and without 
# non-ACGT alphabet. Return seqid and sequence length.
sub process_custom_seq {
    my ($seq_infile, $outfile) = @_;
    open (my $inf, $seq_infile) or die "Could not find $seq_infile!\n";
    open(my $outf, ">$outfile") or die "Could not create $outfile!\n";
    my $line=<$inf>;
    my ($seqid, $seq);
    if ( $line =~ /^>(\S+)/ ) {
        $seqid=$1;
    } else {
        die "Error: Custom seq file $seq_infile is not in fasta format!\n";
    }
	
    while ($line=<$inf>) {
        if ( $line =~ /^>/ ) {
            die "Custom seq file $seq_infile can have only one sequence!\n";
        } else {
            $line =~ s/[^A-Za-z]//g;
            if ( uc($line) =~ /[^ACGT]/ ) {
                 die "Error: $seq_infile contained non-ACGT alphabet.\n" 
            }
			$seq .= uc($line);
        }
    }
    close $inf;
    
    die "No sequence in $seq_infile!\n" if !$seq;

    print $outf ">$seqid\n$seq\n";
    return ($seqid, length($seq));
}

