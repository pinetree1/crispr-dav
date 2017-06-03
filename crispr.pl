#!/usr/bin/env perl
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
    my @samples       = sort keys %{ $h{sample_crisprs} };
    my $total_samples = $#samples + 1;
    my $i             = 0;

    my %jobnames;
    foreach my $sample (@samples) {
        $i++;
        next if -f "$h{align_dir}/$sample.done";

        my $fail_flag = "$h{align_dir}/$sample.failed";
        unlink $fail_flag if -f $fail_flag;

        my $cmd = prepareCommand($sample);
        if ( $h{sge} ) {
            my $jobname = Util::getJobName( "C", "$i" );
            my $cores_per_job = 2;

# set this to at least 2 so as not to overwhelm the system when there are two many samples.
            $cmd =
"qsub -cwd -pe orte $cores_per_job -V -o $h{align_dir}/$sample.log -j y -b y -N $jobname $cmd";
            print STDERR "$cmd\n" if $h{verbose};
            if ( system($cmd) ) {
                die "Failed to submit job for $sample\n";
            }
            $jobnames{$jobname} = $sample;
        }
        else {
            $cmd .= " >$h{align_dir}/$sample.log 2>&1";
            Util::run( $cmd, "Failed in processing sample $sample",
                $h{verbose}, $fail_flag );
        }
    }

    ## wait for jobs to finish
    my $interval     = 120;                         # seconds
    my $max_days     = 2;
    my $max_time     = $max_days * 24 * 60 * 60;    # seconds
    my $elapsed_time = 0;
    my @failures;
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

        if ( $total_samples - $finished <= 2 ) {
            print STDERR "Waiting for "
              . ( $total_samples - $finished )
              . " sample(s) to finish ...\n";
        }

        if ( $h{sge} && $finished == 0 ) {

# If no jobs are on the queue, but they are not indicated as finished either, then exit the program.
            stop_processing( \%jobnames );
        }
    }

    if (@failures) {
        die "Failed in processing samples: "
          . join( ", ", @failures )
          . ". Please check the log files in $h{align_dir}\n";
    }
}

sub crispr_data {
    ## merge crispr-wide data
    my $dir       = $h{align_dir};
    my $hasHeader = 1;
    my @crisprs   = sort keys %{ $h{crispr_samples} };
    my $plot_ext  = $h{high_res} ? "tif" : "png";

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
                }
                else {
                    @infiles = map { "$h{align_dir}/$_.$crispr.$ext" } @samp;
                }

                Util::tabcat( \@infiles, $outfile, $hasHeader );

                my $excel_outfile = "$dest/$crispr" . "_$ext.xlsx";
                Util::tab2xlsx( $outfile, $excel_outfile );
            }

            if ( $ext eq 'cnt' ) {
                my $cmd =
                  "$h{rscript} $Bin/Rscripts/read_stats.R --inf=$outfile";
                $cmd .=
" --outf=$dest/$crispr.readcnt.$plot_ext --rmd=$h{remove_duplicate}";
                $cmd .= " --high_res=$h{high_res}" if $h{high_res};
                Util::run( $cmd, "Failed to create plot of read stats",
                    $h{verbose} );
            }
            elsif ( $ext eq 'chr' ) {
                my $cmd = "$h{rscript} $Bin/Rscripts/read_chr.R --inf=$outfile";
                $cmd .= " --outf=$dest/$crispr.readchr.$plot_ext";
                $cmd .= " --high_res=$h{high_res}" if $h{high_res};
                Util::run( $cmd,
                    "Failed to create plot of read count on chromosomes",
                    $h{verbose} );
            }
            elsif ( $ext eq "pct" ) {

                # create plots for indel count and pct
                my $cmd = "$h{rscript} $Bin/Rscripts/indel.R --inf=$outfile ";
                $cmd .= " --cntf=$dest/$crispr.indelcnt.$plot_ext";
                $cmd .= " --pctf=$dest/$crispr.indelpct.$plot_ext";
                $cmd .= " --high_res=$h{high_res}" if $h{high_res};
                Util::run( $cmd, "Failed to create indel count/pct plots",
                    $h{verbose} );
            }
            elsif ( $ext eq "hdr" and $hdr_bases ) {

                # create HDR plot
                my $cmd =
"$h{rscript} $Bin/Rscripts/hdr_freq.R --inf=$outfile --sub=$crispr";
                $cmd .= " --outf=$dest/$crispr.hdr.$plot_ext";
                $cmd .= " --high_res=$h{high_res}" if $h{high_res};
                Util::run( $cmd, "Failed to create HDR plot", $h{verbose} );
            }
            elsif ( $ext eq "can" ) {

                # create canvasXpress alignment html file
                foreach my $pct ( 0 .. 1 ) {
                    my $cmd =
"$Bin/crispr2cx.pl -input $outfile -perc $pct > $h{deliv_dir}/$crispr/${crispr}_cx$pct.html";
                    Util::run( $cmd,
                        "Failed to create canvasXpress alignment view",
                        $h{verbose} );
                    system($cmd);
                }
            }
        }    # ext

        ## move the image files for individual sample to dest
        foreach my $s (@samp) {
            my @plots = glob("$h{align_dir}/$s.$crispr.*.$plot_ext");
            next if !@plots;
            my $str = join( " ", @plots );
            qx(mv -f $str $dest);
        }

        ## create results html page
        my $cmd = "$Bin/resultPage.pl --ref $h{genome} --gene $h{gene_sym}";
        $cmd .= " --region $h{region} --crispr $h{crispr} --cname $crispr";
        $cmd .= " --nocx" if !$h{canvasXpress};
        $cmd .= " --high_res" if $h{high_res};
        $cmd .= " $h{align_dir} $h{deliv_dir}";
        Util::run( $cmd, "Failed to create results html page", $h{verbose} );
    }    # crispr

    print STDERR "\nAll done!\n";
}

sub prepareCommand {
    my $sample = shift;
    my @fastqs = split( /,/, $h{sample_fastqs}{$sample} );
    die "Fastq input is empty for $sample!\n" if !@fastqs;

    my $cmd = "$Bin/sample.pl $sample $fastqs[0] $h{align_dir}";
    $cmd .= " --read2fastq $fastqs[1]" if $fastqs[1];
    $cmd .= " --picard $h{picard}"     if $h{picard};
    $cmd .= " --abra $h{abra} --prinseq $h{prinseq}";
    $cmd .=
" --samtools $h{samtools} --bwa $h{bwa} --java $h{java} --bedtools $h{bedtools}";
    $cmd .=
      " --pysamstats $h{pysamstats} --rscript $h{rscript} --tmpdir $h{tmpdir}";
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
        It specifies ref_fasta, bwa_idx, min_qual_mean, min_len, etc.

    Specify a reference using --genome or --amp_fasta. Use --genome for standard genomes 
        with fasta file, bwa index, and gene coordinates as specified in configuration 
        file. Use --amp_fasta when trying to use a custom amplicon sequenece as reference. 

    --genome <str> Genome version (e.g. hg19) as specified in configuration file.

    --amp_fasta <str> Amplicon reference fasta file containing a single sequence. 
    --amp_frame <int> Translation starting position in the amplicon reference sequence. 
        If the first codon starts at the first base, then the position is 1. No translation 
        will be performed if the option is omitted. No intron should be present in the 
        amplicon reference sequence if translation is needed. 

    --region <str> Required when --genome option is used. This is a bed file for amplicon region.
        The tab-separated fields are chr, start, end, genesym, refseqid, strand(+/-). 
        No header. All fields are required.
        The start and end are 0-based; start is inclusive and end is exclusive.
        Genesym is gene symbol. Refseqid is used to identify transacript coordinates in 
        refGene coordinate. If refseqid is '-', no alignment view will be created. 

    --crispr <str> Required. A bed file containing one or multiple CRISPR sgRNA sites.
        Information for each site:
        The tab-separated fields are chr, start, end, crispr_name, sgRNA_sequence, strand, 
        and HDR mutations.  All fields except HDR mutations are required. The start and end 
        are 0-based; start is inclusive and end is exclusive. 
        HDR format: <Pos1><NewBase1>,<Pos2><NewBase2>,... The bases are desired bases on 
        positive strand,e.g.101900208C,101900229G,101900232C,101900235A. No space. These 
        positions are 1-based and inclusive. 

    --fastqmap <str> Required. A file containing 2 or 3 columns separated by tab. No header.
        The tab-separated fields are Sample name, read1 fastq file(.gz), and optionally 
        read2 fastq file(.gz).

    --sitemap <str> Required. A file that associates sample name with crispr sites. 
        No header. Each line starts with sample name, followed by one or more crispr 
        sequences. Sample name and crispr sequences are separated by tab.

    --sge Submit jobs to SGE default queue. Your system must already have been configured 
        for SGE.

    --outdir <str> Output directory. Default: current directory.
    --help  Print this help message.
    --verbose Print some commands and information.
";

    my @orig_args = @ARGV;

    my %h;
    GetOptions(
        \%h,           'conf=s',     'genome=s',  'amp_fasta=s',
        'amp_frame=i', 'outdir=s',   'help',      'region=s',
        'crispr=s',    'fastqmap=s', 'sitemap=s', 'sge',
        'verbose'
    );

    die $usage if ( $h{help} or @orig_args == 0 );

    foreach my $opt ( "conf", "crispr", "fastqmap", "sitemap" ) {
        if ( !$h{$opt} ) {
            die "$usage\n\nMissing --$opt.\n";
        }
    }

    if ( ( !$h{genome} && !$h{amp_fasta} ) or ( $h{genome} && $h{amp_fasta} ) )
    {
        die "Must specify --genome or --amp_fasta, but not both!\n";
    }

    $h{pid} = $$;

    $h{outdir} //= ".";

    print STDERR "Main command: $0 @orig_args\n" if $h{verbose};

    ## Output directory
    make_path( $h{outdir} );

    ## parameters in the config file
    my $cfg = Config::Tiny->read( $h{conf} );

    ## tools
    foreach my $tool (
        "abra", "prinseq",  "samtools",   "bwa",
        "java", "bedtools", "pysamstats", "rscript"
      )
    {
        if ( !$cfg->{app}{$tool} ) {
            die "Could not find $tool info in configuration file!\n";
        }

        if ( !-f $cfg->{app}{$tool} ) {
            die "Could not find $cfg->{app}{$tool}!\n";
        }
        $h{$tool} = $cfg->{app}{$tool};
    }

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

    $h{canvasXpress} = 1; # whether to create canvasXpress view of sgRNA on cDNA

    if ( $h{genome} ) {
        $h{genome} =~ s/\s//g;
        if ( !$h{region} ) {
            die "--region must be provided together with --genome!\n";
        }

        if ( !$cfg->{ $h{genome} } ) {
            die "Could not find $h{genome} genome section!\n";
        }
        $h{ref_fasta} = $cfg->{ $h{genome} }{ref_fasta};
        $h{bwa_idx}   = $cfg->{ $h{genome} }{bwa_idx};
        $h{refGene}   = $cfg->{ $h{genome} }{refGene};

        if ( !$h{ref_fasta} or !-f $h{ref_fasta} ) {
            die
"Could not find ref_fasta entry in $h{conf} or the reference fasta file!\n";
        }

        if ( !$h{bwa_idx} or !-f "$h{bwa_idx}.bwt" ) {
            die
"Could not find bwa_index entry in $h{conf} or the bwa index files!\n";
        }

        if ( $h{refGene} && !-f $h{refGene} ) {
            die "Could not find refGene file $h{refGene}!\n";
        }

    }
    elsif ( $h{amp_fasta} ) {
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
        print $tmpf join( "\t", $seqid, 0, $len, $seqid . "_CR", $seqid, "+" )
          . "\n";
        close $tmpf;

        $h{canvasXpress} = 0;

        # Create coordinate file for translation
        if ( $h{amp_frame} ) {
            $h{refGene} = "$h{outdir}/amplicon.frame";
            $h{geneid}  = $seqid;
            open( my $tmpf, ">$h{refGene}" ) or die $!;
            print $tmpf join( "\t",
                "#bin",      "name",       "chrom",    "strand",
                "txStart",   "txEnd",      "cdsStart", "cdsEnd",
                "exonCount", "exonStarts", "exonEnds" )
              . "\n";
            print $tmpf join( "\t",
                "0", $seqid, $seqid, "+", $h{amp_frame} - 1,
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

    #$h{tmpdir}           = $cfg->{other}{tmpdir};
    $h{wing_length}   = $cfg->{other}{wing_length};
    $h{cores_per_job} = $cfg->{other}{cores_per_job};
    $h{high_res}      = $cfg->{other}{high_res};

    # Defaults:
    $h{remove_duplicate} //= "N";
    $h{realign_flag}     //= "Y";
    $h{min_mapq}         //= 20;
    $h{tmpdir}           //= "/tmp";
    $h{wing_length}      //= 40;
    $h{cores_per_job}    //= 2;
    $h{high_res}         //= 0;

    ## Directories
    $h{align_dir} = "$h{outdir}/align";
    $h{deliv_dir} = "$h{outdir}/deliverables";
    $h{tmpdir}    = "$h{outdir}/align/tmp";
    make_path( $h{align_dir}, $h{deliv_dir}, $h{tmpdir} );

    ## amplicon and crisprs
    my ( $amp, $crisprs, $sample_crisprs, $crispr_samples ) =
      processBeds( $h{region}, $h{crispr}, $h{sitemap} );

    $h{chr}            = $amp->[0];
    $h{amplicon_start} = $amp->[1] + 1;
    $h{amplicon_end}   = $amp->[2];
    $h{gene_sym}       = $amp->[3];
    $h{geneid}         = $amp->[4];
    $h{gene_strand}    = $amp->[5];

    $h{crisprs}        = $crisprs;
    $h{sample_crisprs} = $sample_crisprs;
    $h{crispr_samples} = $crispr_samples;

    if ( $h{geneid} eq "-" ) {
        $h{canvasXpress} = 0;
    }

    ## fastq files
    $h{sample_fastqs} = getFastqFiles( $h{fastqmap} );
    print Dumper( $h{sample_fastqs} ) . "\n" if $h{verbose};

    foreach my $key ( sort keys %h ) {
        print STDERR "$key => $h{$key}\n" if $h{verbose};
    }

    ## ensure all samples in sitemap are present in fastqmap
    foreach my $s ( keys %{ $h{sample_crisprs} } ) {
        if ( !defined $h{sample_fastqs}{$s} ) {
            die "Error: Sample $s in sitemap is not found in fastqmap!\n";
        }
    }

    print STDERR "\nCRISPR info:\n" . Dumper( $h{crisprs} ) if $h{verbose};
    print STDERR "\nCRISPR samples:\n" . Dumper( $h{crispr_samples} )
      if $h{verbose};
    return %h;
}

sub processBeds {
    my ( $amp_bed, $crispr_bed, $sitemap ) = @_;
    die "Could not find $amp_bed!\n"    if !-f $amp_bed;
    die "Could not find $crispr_bed!\n" if !-f $crispr_bed;
    die "Could not find $sitemap!\n"    if !-f $sitemap;

    ## amplicon bed
    open( my $ampf, $amp_bed ) or die $!;
    my @amp;
    my $cnt = 0;
    while ( my $line = <$ampf> ) {
        next if ( $line =~ /^\#/ or $line !~ /\w/ );
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
        die "Error: $amp_bed did not have 6 columns.\n";
    }
    else {
        checkBedCoord( $amp[1], $amp[2], "Error in $amp_bed" );
    }

    if ( $cnt > 1 ) {
        die "Only one amplicon is allowed. No header is allowed.\n";
    }

    $amp[4] =~ s/\s//g;
    $amp[5] =~ s/\s//g;
    $amp[5] = uc( $amp[5] );
    die "Strand must be + or - in bed file!\n" if $amp[5] !~ /[+-]/;

    my $MIN_AMP_SIZE = 50;
    if ( $amp[2] - $amp[1] < $MIN_AMP_SIZE ) {
        die
"Error: Amplicon size too small! Must be at least $MIN_AMP_SIZE bp.\n";
    }

    # ensure each crispr site range is inside amplicon range

    # store crispr info
    my %crisprs;    # name=>chr,start,end,seq,strand,hdr

    open( my $cb, $crispr_bed ) or die "Could not find $crispr_bed.\n";
    my %crispr_names;    # {seq}=>name
    while ( my $line = <$cb> ) {
        next if ( $line !~ /\w/ || $line =~ /^\#/ );
        chomp $line;
        my ( $chr, $start, $end, $name, $seq, $strand, $hdr ) =
          split( /\t/, $line );
        $name =~ s/\s//g;
        $seq  =~ s/\s//g;
        $seq = uc($seq);
        $hdr =~ s/\s//g;
        die "Strand must be + or - in bed file!\n" if $strand !~ /[+-]/;

        checkBedCoord( $start, $end, "Error in $crispr_bed" );

        if ( $chr ne $amp[0] ) {
            die
"Error: crispr $name\'s chromosome $chr does not match $amp[0] in amplicon bed.\n";
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
        my @a = split( /\t/, $line );
        die "There were not sufficient tab-separated columns in: $line\n"
          if @a < 2;
        my $sample = shift @a;
        next if !$sample;
        $sample =~ s/\s//g;

        if ( $seen_samples{$sample} ) {
            die "Sample name $sample is duplicated in $sitemap\n";
        }
        $seen_samples{$sample} = 1;

        my $found_seq = 0;
        foreach my $seq (@a) {
            $seq =~ s/\s//g;
            next if !$seq;
            $seq = uc($seq);
            die "Sequence $seq contained non-ACGT letter!\n"
              if $seq !~ /[ACGT]/;
            $found_seq                                      = 1;
            $sample_crisprs{$sample}{ $crispr_names{$seq} } = 1;
            $crispr_samples{ $crispr_names{$seq} }{$sample} = 1;
        }
        die "No crispr sequence in $line!\n" if !$found_seq;
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

    while ( my $line = <$fh> ) {
        chomp $line;
        my @a = split( /\t/, $line );
        my $sample = shift @a;
        next if !$sample;
        $sample =~ s/\s//g;

        my @b;

        # ensure fastq files exist
        foreach my $f (@a) {
            next if !$f;
            if ( !-f $f or -z $f ) {
                push( @errors, "$f was not found or empty" );
            }
            elsif ( $f !~ /\.gz$/ ) {
                push( @errors, "$f was not .gz file" );
            }
            else {
                push( @b, $f );
            }
        }

        if (@b) {
            $fastqs{$sample} = join( ",", @b );
        }
        else {
            push( @errors, "No fastq file for $sample" );
        }
    }
    close $fh;

    if (@errors) {
        die "Fastq file errors: \n"
          . join( "\n",
            @errors,
            "Note: all fields in $filemap must be separated by tab\n" );
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
        }
        else {
            $line =~ s/[^atcgnATCGN]//g;
            $len += length($line);
        }
    }
    close $tmpf;

    die "Error: no sequence ID in $fasta.\n" if !$seqid;
    die "Error: no sequence in $fasta.\n"    if !$len;

    return ( $seqid, $len );
}

sub checkBedCoord {
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
        die "$msg:\n" . join( "\n", @errs );
    }
}

sub check_pysam {
    my $pysamstats = shift;
    if ( system("$pysamstats --help > /dev/null") ) {
        my $msg =
"$pysamstats does not run properly. If there is error importing a module,";
        $msg .=
          " please include the module path in environment variable PYTHONPATH.";
        die "$msg\n";
    }
}

sub check_perlmod {
    my @mods = qw(Config::Tiny
      Excel::Writer::XLSX
      Spreadsheet::ParseExcel
      Spreadsheet::XLSX
      Time::HiRes
      JSON
      CGI
      URI::Escape
      Bio::PrimarySeq
    );

    foreach my $mod (@mods) {
        eval("use $mod");
        die "Cannot find $mod!\n" if $@;
    }
}

sub stop_processing {
    my $href = shift;

# If no jobs are on the queue, but they are not indicated as finished either, then exit the program.
    my $queue_jobs = Util::getJobCount($href);
    return if $queue_jobs;

    my $delay = 360;
    sleep $delay;

    my $log_cnt  = 0;
    my %jobnames = %{$href};
    while ( my ( $j, $s ) = each %jobnames ) {
        if ( -f "$h{align_dir}/$s.log" ) {
            $log_cnt++;
        }
    }

    my @done   = glob("$h{align_dir}/*.done");
    my @failed = glob("$h{align_dir}/*.failed");
    if ( $log_cnt && !@done && !@failed ) {
        print STDERR "Queued jobs have failed. Progam exited.\n";
        system("kill $h{pid}");
        exit 1;
    }
}
