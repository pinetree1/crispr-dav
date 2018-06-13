#!/usr/bin/env perl
# Prepare run script and input files for CRISPR-DAV pipeline
use strict;
use FindBin qw($Bin);
use lib "$Bin/Modules";
use PreProcess;
use File::Path qw(make_path);
use File::Basename;
use Getopt::Long;

my $usage = "Usage: $0 [options] {samplesheet}
  --conf     <str>  Crispr configuration file. Default: $Bin/conf.txt
  --outdir   <str>  Output directory. Default: current directory.
  --fastqdir <str>  Raw fastq path. This overwrite paths in the samplesheet.
  --project  <str>  Project ID. This overwrite the project ID in samplesheet.
  --no-merge        Do not merge paired-end reads.
  --sge             Submit jobs to SGE queue if available. 
";

GetOptions('conf=s'=>\my $conf,
        'outdir=s'=>\my $outdir,
        'fastqdir=s'=>\my $fastqdir,
        'projectid=s'=>\my $projectid,
        'no-merge'=>\my $no_merge_flag,
        'sge'=>\my $sge_flag
       );

die $usage if @ARGV !=1;
$outdir //= ".";
$conf //= "$Bin/conf.txt";
my $samplesheet = $ARGV[0];

die "$conf not found!\n" if !-f $conf;
die "$samplesheet not found!\n" if !-f $samplesheet;
die "$fastqdir does not exist!\n" if $fastqdir && !-d $fastqdir;

my $p = new PreProcess();
my $genomes = $p->getGenomes($conf);

print STDERR "Processing samplesheet ...\n";
my ($ordered_amps, $samples, $fastqDirs, $projects, $genesyms, $guides, $ordered_guides,
    $hdrs) = $p->parseSamplesheet($samplesheet, $genomes, $fastqdir, $projectid); 

my $prep_dir = "$outdir/prep";
make_path($prep_dir);

my @amp_paths;
my $i = 0;

foreach my $amp ( @$ordered_amps ) {
    $i++;
    my ($genome, $chrom, $amp_start, $amp_end)=split(/[,:-]/, $amp);
    my @syms = keys %{$genesyms->{$amp}};
    my $genesym = $syms[0];
    my $guide_aref = $ordered_guides->{$amp};
    my $hdr_href = $hdrs->{$amp};    
    my @project_ids = keys %{$projects->{$amp}}; 

    $p->checkGenome($genomes, $genome);

    my $amp_path = "$prep_dir/" . join("_", "amp", $genesym, $chrom, $amp_start, $amp_end);
    $amp_path = File::Spec->rel2abs($amp_path);
    make_path($amp_path);
    push(@amp_paths, $amp_path);

    ## prepare fastq list
    my $fastq_list = "$amp_path/fastq.list";
    $p->createFastqList($samples->{$amp},
                      $fastqDirs->{$amp}, $fastq_list);

    # create sample/site list 
    my $site_list = "$amp_path/sample.site";
    $p->createSiteList($guides->{$amp}, $guide_aref, $site_list);

    # create project.conf file
    my $proj_conf="$amp_path/project.conf";
    $p->createProjectConf($project_ids[0], $genome, $chrom, $amp_start, 
          $amp_end, $guide_aref, $hdr_href, $proj_conf);

    # create amplicon.bed and site.bed
    my $amp_bed = "$amp_path/amplicon.bed"; 
    my $site_bed = "$amp_path/site.bed";
    $p->createBeds($genesym, $genome, $chrom, $amp_start, $amp_end,
          $guide_aref, $hdr_href, $genomes->{$genome}{bwa_idx}, 
          $genomes->{$genome}{refGene}, $amp_path,
          $amp_bed, $site_bed);

    # copy files
    qx(cp $samplesheet $amp_path);
    qx(cp $conf "$amp_path/conf.txt");

    # create run script
    my $run_scriptname = "run.sh";
    $p->createRunScript($amp_path, $genome, $run_scriptname, $no_merge_flag, $sge_flag);

    if ( !-f "$amp_path/$run_scriptname" ) {
        die "Failed to create run script for amplicon $genome $chrom:$amp_start-$amp_end.\n"; 
    } 
}

print STDERR "Successfully created amplicon directories in $outdir:\n";
foreach my $path ( @amp_paths ) {
    my $amp_name = basename($path); 
    if (system ("mv $path $outdir")==0 ) {
        print STDERR "  $amp_name\n";
    } 
}

# remove temporary prep directory
qx(rm -rf $prep_dir);

