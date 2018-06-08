package PreProcess;

=head1 DESCRIPTION

Validate samplesheet, and create input files for core pipeline

=head1 AUTHOR

Xuning Wang

=cut

use strict;
use File::Basename;
use File::Path qw(make_path);
use Data::Dumper;
use FindBin qw($Bin);
use Config::Tiny;
use Carp qw(croak);

=head2 new

 Function: Create a PreProcess object.

=cut

sub new {
    my $self = shift;
    my %h = ();
    bless \%h, $self;
}

=head2 getGenomes

 Function: Gather genome infomation from configuration file.
 Args    : conf is a a configuration file for the pipeline.
 Returns : A hash of genome information.

=cut

sub getGenomes {
    my ($self, $conf) = @_;
    my $cfg = Config::Tiny->read($conf);
    my $genomes;
    foreach my $k (keys %{$cfg}) {
        if ( $cfg->{$k}{ref_fasta} ) {
            $genomes->{$k}{ref_fasta}=$cfg->{$k}{ref_fasta};
            if ( !$cfg->{$k}{refGene} ) {
                croak "Error: no refGene entry for $k in config file!\n";
            }
            $genomes->{$k}{refGene}=$cfg->{$k}{refGene};
            
            if ( !$cfg->{$k}{bwa_idx} ) {
                croak "Error: no bwa_idx entry for $k in config file!\n";
            }
            $genomes->{$k}{bwa_idx}=$cfg->{$k}{bwa_idx};
        }
    }
    return $genomes;
}

=head2 xls2tsv 

 Function: convert Excel file (.xlsx) to tab delimited text file.
 Args    : infile, outfile, sheetname (default: first sheet is used) 
           infile is an Excel file
           outfile is optional. If omitted, it will be the same file name 
               as infile but with .xlsx replaced with .txt.
 Requires: Spreadsheet::XLSX module is required.

=cut
       
sub xls2tsv{
    my ($self, $infile, $outfile, $sheet_name) = @_;
    require Spreadsheet::XLSX; 
    open(my $in, $infile) or croak "Cannot open $infile\n";
    my ($base, $path)=fileparse($infile, qr/\.[^.]*$/);
    if (!$outfile) {
        $outfile = "$path/$base.txt";
    } 
    
    open(my $outfh, ">$outfile") or croak "Cannot create $outfile\n";   
    my $excel = Spreadsheet::XLSX->new($infile);
    foreach my $sheet (@{$excel->{Worksheet}}) {
        my $sn = $sheet->{Name};
        if ($sheet_name) {
            if ($sheet_name eq $sn) {
                printSheet($sheet, $outfh);  
            }
        } else {
            printSheet($sheet, $outfh);
            last;
        }
    }
}

=head2 printSheet

 Function: output an Excel sheet to tsv file. 
 Args    : Excel sheet object, output file handle.

=cut

sub printSheet {
    my ($sheet, $outfh) = @_;
    $sheet -> {MaxRow} ||= $sheet -> {MinRow};
    foreach my $row ($sheet -> {MinRow} .. $sheet -> {MaxRow}) {
        $sheet -> {MaxCol} ||= $sheet -> {MinCol};
        my @tmp;
        foreach my $col ($sheet -> {MinCol} ..  $sheet -> {MaxCol}) {
            my $cell = $sheet -> {Cells} [$row] [$col];
            # remove potential characters: quote, line feed
            $cell->{Val} =~ s/[\"\n\r]//g;
            push (@tmp, $cell->{Val});
        }
        print $outfh join("\t", @tmp) . "\n";
    }
}

=head2 createProjectConf 

 Function: Create project config file.

=cut

sub createProjectConf {
    my ($self, $project_id, $genome, $chr, $start, $end,
        $guide_aref, $hdr_href, $outfile)=@_;

    open(my $outf, ">$outfile") or die $!;

    my @sgRNA_seqs = @$guide_aref;
    my $guide_seqstr = join(",", @sgRNA_seqs);

    my @base_changes;
    foreach my $seq ( @sgRNA_seqs ) {
        push(@base_changes, $hdr_href->{$seq});
    };

    my $hdr_str= join(";", @base_changes); # use ; as separator

    print $outf "project_id = $project_id
genome_version = $genome
chromosome = $chr
amplicon_range = $start - $end
sgRNA_sequences = $guide_seqstr
HDR_changes= $hdr_str
";
    close $outf;
}

=head2 createSiteList

 Function: Create a file that list all sgRNA sequences for a sample.

=cut

sub createSiteList {
    my ($self, $guides, $guide_aref, $outfile) = @_;
    # guides: {sampleName}{seq}
    open(my $outf, ">$outfile") or die $!;
    foreach my $s ( sort keys %{$guides} ) {
        my @g = keys %{$guides->{$s}};
        if ( scalar(@g)==1 and $g[0] eq "CONTROL" ) {
            @g = @$guide_aref;
        }    

        print $outf join("\t", $s, @g) . "\n";
    }
    close $outf;
}

=head2 createFastqList

 Function: Create a file with 3 columns: sample name, fastq1, fastq2. 

=cut

sub createFastqList {
    my ($self, $samp, $fdir, $outfile) = @_; 
    #samp: {samplename}{sampleID}
    #fdir: {samplename}{fastqdir}
    open (my $outf, ">$outfile") or die "Could not create $outfile\n";
    my @failed_samples;
    foreach my $s ( sort keys %{$samp} ) {
        my @sid = keys %{$samp->{$s}};
        my @dir = keys %{$fdir->{$s}};
        my @files = getFastqFiles($sid[0], $dir[0]);    
        if ( !@files ) {
            push(@failed_samples, $s);
        } else {
            print $outf join("\t", $s, @files) . "\n";
        }
    }
    close $outf;

    if ( @failed_samples ) {
        croak "Could not find fastq files for " .join(", ", @failed_samples) . "\n";
    } 
}

=head2 getFastqFiles

 Function: Find the single-end or paired-end fastq files for a sample.
           The fastq files must end with .gz.
           If present, fastq files for index reads should have _I1_ or _I2_ in file
           name so that they will not be considered as fastq files for regular reads.
 Returns : an array of up to 2 fastq files. 

=cut

sub getFastqFiles {
    my ($sample_id, $dir) = @_;
    croak "Fastq directory s3 path is not accepted.\n" if $dir =~ /^s3:/;
    my @fs = sort glob("$dir/${sample_id}*.gz");
    if ( !@fs ) {
        croak "Could not find fastq files that start with $sample_id and end with .gz";
    }
 
    my @files;
    foreach my $f ( @fs ) {
        if ( basename($f) =~ /^${sample_id}.*_I[12]_.*/ ) { 
            # This may be index files. Skip.
            next;
        } elsif ( basename($f) =~ /^${sample_id}/ ) {
            push(@files, $f);
        }
    }    

    if ( scalar(@files) > 2 ) {
        croak "Error: cannot have more than 2 files for $sample_id: ".join(",", @files)."\n";
    } 

    return @files;       
}

=head2 parseSamplesheet

 Function: Parse samplesheet tsv or xlsx file. The samplesheet has 2 header rows.
           The column order is: genesym, genome, amplicon range, guide sequence, HDR,
                 sample name, sample ID, projectID, fastq dir path 
 Args    : samplesheet, genome reference(returned by getGenomes), fastqdir, projectid
           Fastqdir is optionl. If specified, it overwrites the fastq dirpath in samplesheet.
           Projectid is optional. If specified, it overwrites the project in samplesheet.
          

 Returns : a series of hashes 

=cut

sub parseSamplesheet {
    my ($self, $infile, $genomes, $fastqdir, $projectid) = @_;

    if ($fastqdir && $fastqdir !~ /^s3:/ && !-d $fastqdir) {
        croak "Fastq directory $fastqdir does not exist!";
    }

    # One spreadsheet can have multiple genomes.
    ## General conditions of the input within the same amplicon:
    #0. An amplicon is defined as:genome,amplicon_range. Error if no complete info. 
    #1. One sample name can have only 1 sample ID and vice versa. But {amp}{sample}{sampleID} is unique
    #3. A sample can have more than 1 row because of multiple sgRNA.
        #{amplicon}->{sgRNA}->[sample1, sample2, ...]. Must have >0 sample
    #4. A sample can have only one fastq dir. {amp}{sample}{fqdir}
        #{amplicon}->{sample}=>fastq_path
    #6. A control sample does not need to have sgRNA, but still need amplicon info.
    #7. An amplicon can have only one projectID. {amp}{proj}
    #8. An amplicon cna have only one Genesym.
    # Create input files for each amplicon 
    # Report guide sequence that can't align with reference.

    if ( $infile =~ /(.*)\.xlsx$/ ) {
        my $base=$1;
        $self->xls2tsv($infile);
        $infile="$base.txt";
    }
    qx(dos2unix -q $infile);

    open(my $inf, $infile) or croak $!;

    ## skip the first 2 lines;
    <$inf>; <$inf>; 

    my @ordered_amps;
    my %seen_amps;
    my %samples; 
    my %samples2;
    my %fastqDirs;
    my %projects;
    my %genesyms;
    my %guides; # used for sample site list
    my %ordered_guides;
    my %seen;
    my %hdrs;
    my %amp_guides; # {amp}{guide}=1
    my %guide_amps; # {guide}=amp

    # get a list of lower cased genome names
    my %genomeNames;
    foreach my $gn ( keys %$genomes ) {
        $genomeNames{lc($gn)} = $gn; 
    } 

    my @errors;
    my $i = 2;
    my $prev_end = 0;  # end coordinate of previous amplicon
    while (my $line=<$inf>) {
        $i++;
        next if ($line !~ /\w/ or $line =~ /^#/);
        chomp $line;

        # Keep only allowed chars: \w (digit, letter, _) , -, comma, :, and \t.
        $line =~ s/[^\w\t,\/:\-]//g;  # space is removed

        my ($genesym, $genome, $range, $sgRNA, $hdr, $sampleName, $sampleID, 
             $project, $fqdir) = split(/\t/, $line);

        if (!$genesym or !$genome or !$range or !$sampleName or !$sampleID ) {
            push(@errors, "Line $i: Empty value for genesym, genome, amplicon, sampleName or sampleID. If the affected field is not empty, this error could be caused by inserted or missing columns.");
            next;
        }

        # Genesym
        $genesym=uc($genesym);
        $genesym =~ s/\-/_/g;  # replace - in gene symbol with _

        # Genome
        if ($genomeNames{lc($genome)}) {
            $genome = $genomeNames{lc($genome)};
        } else {
            push(@errors, "Line $i: Genome $genome was not found in configuration file."); 
        }

        # Amplicon range
        $range =~ s/,//g;
        if ( $range !~ /^[^:]+:\d+\-\d+$/ ) {
            push(@errors, "Line $i: Amplicon range's format is incorrect");
        }
        my ($chr, $start, $end) = split(/[:-]/, $range);
        if ( $end == $prev_end + 1 ) {
            push(@errors, "Line $i: Amplicon range is only 1 greater than previous entry! Possibly an Excel error.");
        }
        $prev_end = $end;

        if ( $chr =~ /^chr/i ) {
            $chr = lc($chr);
            $chr =~ tr/xy/XY/;
        }

        if ( $start > $end ) {
            my $tmp = $start;
            $start = $end;
            $end = $tmp; 
        }

        # Guide sequences
        if ( $sgRNA =~ /[^ATCGU,]/i ) {
           push(@errors, "Line $i: incorrect sequence: $sgRNA");
        }

        $sgRNA = uc($sgRNA);
        if ( $sgRNA eq "" ) {
            $sgRNA = "CONTROL";
        } else {
            $sgRNA =~ s/U/T/g;
        }
       
        # HDR information 
        if ( $hdr =~ /[^ATCG,\d]/i ) {
            push(@errors, "Line $i: incorrect HDR format");
        }
        $hdr = uc($hdr);

        # sample name: meaningful name to scientist
        $sampleName =~ s/,//g;
      
        # Project ID
        $project = $projectid if $projectid;
 
        # fastq path 
        $fqdir = $fastqdir if $fastqdir;

        if ( $fqdir !~ /\w/ ) {
            push(@errors, "Line $i: Fastq directory is empty and not specified on command line");
        } elsif ( $fqdir =~ /^s3:/ ) { 
            push(@errors, "Line $i: Fastq directory should not be s3 path!");
        } elsif ( ! -d $fqdir ) {
            push(@errors, "Line $i: $fqdir does not exist!");
        }
        
        $fqdir = File::Spec->rel2abs($fqdir);

        my $amp = "$genome,$chr:$start-$end";
        if ( !$seen_amps{$amp} ) {
            $seen_amps{$amp} = 1;
            push(@ordered_amps, $amp);
        }

        $genesyms{$amp}{$genesym} = 1;
        $projects{$amp}{$project} = 1;
        $samples{$amp}{$sampleName}{$sampleID} = 1;
        $samples2{$amp}{$sampleID}{$sampleName} = 1;
        $fastqDirs{$amp}{$sampleName}{$fqdir} = 1;

        foreach my $sg ( split (/,/, $sgRNA) ) {    
            $sg =~ s/U/T/g;
            if ( $sg ne "CONTROL" ) {
                if ( !$guide_amps{$sg} ) {
                    $guide_amps{$sg} = $amp;
                } elsif ( $guide_amps{$sg} ne $amp ) {
                    push(@errors, "Line $i: amplicon range should not differ for the same guide."); 
                }
            }

            $guides{$amp}{$sampleName}{$sg} = 1;
            if ( $hdr ) {
                $hdrs{$amp}{$sg}=$hdr;
            }

            if ( $sg ne "CONTROL" && !$seen{$amp}{$sg} ) {
                push(@{$ordered_guides{$amp}}, $sg);
                $seen{$amp}{$sg}=1;
            }

            $amp_guides{$amp}{$sg}=1;
        }
    }
    close $inf;

    # More error checking
    foreach my $amp ( sort keys %genesyms ) {
        my @syms = keys %{$genesyms{$amp}};
        push(@errors, "$amp had more than 1 genesym: " . join(",", @syms)) if @syms > 1;

        my @projs = keys %{$projects{$amp}};
        push (@errors, "$amp had more than 1 project: " . join(",", @projs)) if @projs > 1;

        foreach my $sampleName ( sort keys %{$fastqDirs{$amp}} ) {
            my @fqs = keys %{$fastqDirs{$amp}{$sampleName}};
            push (@errors, "$sampleName in amplicon $amp had more than " . 
                  "1 fastq dir: " . join(", ", sort (@fqs))) if @fqs > 1;
        }

        foreach my $sampleName ( sort keys %{$samples{$amp}} ) {
            my @sampleIDs = keys %{$samples{$amp}{$sampleName}};
            push (@errors, "$sampleName matched to more than 1 Sample ID") if @sampleIDs > 1;
        }

        foreach my $sampleID ( sort keys %{$samples2{$amp}} ) {
            my @sampleNames = keys %{$samples2{$amp}{$sampleID}};
            push (@errors, "$sampleID matched to more than 1 Sample Name") if @sampleNames > 1;
        }


        my @tmp_guides = keys %{$amp_guides{$amp}}; 
        if ( scalar(@tmp_guides)==1 && $tmp_guides[0] eq "CONTROL" ) {
            push(@errors, "$amp has only control, no treatment sample!");
        }
    }

    if ( @errors ) {
        print join("\n", "Errors:", @errors) . "\n";
        exit;
    }

    return (\@ordered_amps, \%samples, \%fastqDirs, \%projects, 
       \%genesyms, \%guides, \%ordered_guides, \%hdrs); 
}



=head2 createBeds

 Function: To create amplicon.bed and site.bed. 
           In these files, start position is 0-based, end position is 1-based. 
 
=cut

sub createBeds {
    my ($self, $genesym, $genome, $chrom, $amp_start, $amp_end, 
        $guide_aref, $hdr_href,
        $bwa_idx, $refgene_file, $work_dir, 
        $amplicon_bed_outfile, $site_bed_outfile) = @_;
   
    my %guide_info = getGuideInfo($guide_aref, $chrom, $bwa_idx, $refgene_file, $work_dir);

    my %genes; 

    ## Output to site bed file
    open(my $sitef, ">$site_bed_outfile") or die "Cannot create site bed file!\n";

    foreach my $seq ( @$guide_aref ) {
        my ($chr, $start, $end, $guideName, $strand, 
           $refseq_sym, $refseq_ID, $txStart, $txEnd, $txStrand) = split(/\t/, $guide_info{$seq});

        if ( $refseq_sym ) {
            $genesym = $refseq_sym;
        }
        $genesym = uc($genesym);

        if ( !$refseq_ID ) {
            print STDERR "refSeq ID not found in refGene table. Have set it to -.\n";
            $refseq_ID = "-";
        }

        if ( !$txStrand ) {
            print STDERR "Could not find txStrand in refGene table. Set it to +.\n";
            $txStrand = '+';
        }

        $genes{$genesym}=join("\t", $refseq_ID, $chr, $txStart, $txEnd, $txStrand);

        print $sitef join("\t", $chr, $start-1, $end, $guideName, $seq, 
                           $strand, $hdr_href->{$seq}) . "\n";
    }
    close $sitef;


    ## Output to amplicon bed file

    open(my $ampf, ">$amplicon_bed_outfile") or die "Cannot create $amplicon_bed_outfile!\n";
    my @genesyms = keys %genes;

    foreach my $sym ( @genesyms ) {
        my ($refseqID, $chr, $txStart, $txEnd, $txStrand) = split(/\t/, $genes{$sym});

        # use supplied amplicon coordinates
        if ( $amp_start ) {
            $txStart = $amp_start-1;
        }

        if ( $amp_end ) {
            $txEnd = $amp_end;
        }

        print $ampf join("\t", $chr, $txStart, $txEnd, $sym, $refseqID, $txStrand) . "\n";
    }
    close $ampf;

    if ( scalar(@genesyms) > 1 ) {
        croak "Error: The guide sequences in the amplicon matched to more than one gene!\n";
    }
}

=head2 getGuideInfo

 Function: To locate sgRNA guide in genome and refGene table.
 Returns : A hash of guideseq=> chr, start, end, seq, strand, genesym, refseqid, tx_start, tx_end, tx_strand.
           All chromosome coordinates are 1-based.

=cut

sub getGuideInfo {
    my ($guide_aref, $known_chrom, $bwa_idx, $refgene_file, $work_dir ) = @_;

    ## create a fasta file
    my $guide_fasta = "$work_dir/guides.fa";
    open(my $outf, ">$guide_fasta") or die "Cannot create $guide_fasta.\n";
    foreach my $seq ( @$guide_aref ) {
        print $outf ">$seq\n$seq\n";
    }
    close $outf;

    ## bwa alignment
    my $sam = "$work_dir/guides.sam";
    my $cmd = "bwa aln $bwa_idx $guide_fasta 2>/dev/null |";
    $cmd .= " bwa samse $bwa_idx - $guide_fasta > $sam 2>/dev/null";
    my $status = system($cmd);
    if ($status) {
        croak  "Failed in aligning guide sequence!\n";
    }

    ## parse alignment result
    my %guide_info; 

    foreach my $line (split(/\n/, qx(grep -v \@ $sam))) {
        my @a = split(/\t/, $line);
        next if $a[5] =~ /H/; # $a[5] is cigar 
        my $seq = $a[0];
        my ($chr, $start, $end, $strand) = parseSamRecord($line, $known_chrom); 
        croak  "Error: Could not find $seq in reference genome!\n" if !$chr;

        my @refgene_info = getRefGeneInfo($chr, $start, $end, $refgene_file);    
        $guide_info{$seq} = join("\t", $chr, $start, $end, $seq, $strand, @refgene_info ); 
    }
    return %guide_info;
}

=head2 parseSamRecord

 Function: Parse SAM record and return coordinate info. 

=cut

sub parseSamRecord {
    my ($line, $inputchr) = @_;
    chomp $line;

    my ($query, $flag, $chr, $start, $mapq, $cigar)= split(/\t/, $line);    
    my $strand = $flag & 16 ? '-' : '+';
    my ($mismatch) = ( $line =~ /\tNM:i:(\d+)\t/ );
    my @candidates;
    push(@candidates, [$chr, $start, $strand, $cigar, $mismatch]);     

    # alternative matches, like: XA:Z:chr10,-97604287,20M,0;chr2,-70164342,20M,1;
    my ($alt) = ( $line =~ /\tXA:Z:(\S+);/ );    
    foreach my $str ( split(/;/, $alt) ) {
        ($chr, $start, $cigar, $mismatch)=split(/,/, $str);
        ($strand, $start) = $start =~ /([+-])(\d+)/;
        push(@candidates, [$chr, $start, $strand, $cigar, $mismatch]);
    }

    my $len = length($query);
    foreach my $can ( @candidates ) {
        ($chr, $start, $strand, $cigar, $mismatch) = @$can;
        if ( $mismatch == 0 && $cigar eq "${len}M" && $inputchr eq $chr ) {
            return ($chr, $start, $start+$len-1, $strand);
        }
    }
}

=head2 getRefGeneInfo

 Function: Find gene info from refGene table.

=cut

sub getRefGeneInfo {
    my ($chr, $start, $end, $refGeneTable)=@_;
    croak "Could not find $refGeneTable.\n" if !-f $refGeneTable;

    open(PP, "awk '\$3==\"$chr\"' $refGeneTable |");

    my $longest = 0;
    my ($tx_start, $tx_end, $genesym, $refseqid, $tx_strand);
    while ( <PP> ) {
        chomp;
        my @a = split /\t/, $_;
        my $txChr    = $a[2];
        my $txStart    = $a[4]; # 0-based
        my $txEnd    = $a[5]; # 1-based
        if ( $txChr eq $chr && $txStart < $start && $end <= $txEnd ) {
            if ( !$longest or $txEnd - $txStart > $longest ) {
                $longest = $txEnd - $txStart;
                $refseqid= $a[1];
                $genesym = $a[12];
                $tx_start = $txStart+1;
                $tx_end = $txEnd;        
                $tx_strand = $a[3];
            }
        }    
    }
    close PP;
    if ( $longest ) {
        return ($genesym, $refseqid, $tx_start, $tx_end, $tx_strand);    
    }
    return ();
}

=head2 createRunScript

 Function: Generate the run.sh script.

=cut

sub createRunScript {
    my ($self, $amp_dir, $genome, $script_name, $no_merge_flag, $sge_flag) = @_;
    my @required=("amplicon.bed", "conf.txt", "fastq.list", 
           "project.conf", "sample.site", "site.bed");
    my @missing;
    foreach my $f ( @required ) {
        if ( !-f "$amp_dir/$f" ) {
            push(@missing, $f);
        } 
    }
    if ( @missing ) {
        croak "Could not create run.sh due to missing files: " . join(",", @missing) . "\n";
    }

    open(my $outf, ">$amp_dir/$script_name") or croak "Failed to create run script";
    if ( -f "$Bin/setup_env.sh" ) {
        print $outf "source $Bin/setup_env.sh\n";
    }

    my $cmd = "$Bin/crispr.pl --conf conf.txt --region amplicon.bed --crispr site.bed \\\n";
    $cmd .= " --sitemap sample.site --fastqmap fastq.list --genome $genome --verbose";
    $cmd .= " --merge N" if $no_merge_flag;
    $cmd .= " --sge" if $sge_flag; 
    print $outf "$cmd\n";
    close $outf;
}

1;
