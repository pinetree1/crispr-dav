#!/usr/bin/env perl
# Creates html page
# Author: X. Wang

use 5.010;
use strict;
use File::Basename;
use Getopt::Long;
use File::Path qw(make_path);
use FindBin qw($Bin);

my $usage = "Usage: $0 [option] indir outdir
    --ref     <str> reference name, e.g. hg19. Required.	
    --gene    <str> Gene name, e.g. FPR2. Required.
    --region  <str> a bed file of amplicon. Required.
    --crispr  <str> a bed file containing sgRNA region. Required.
    --cname   <str> Name of CRISPR site. Optional. 
    --nocx    Do not to create canvasXpress alignment view 
    --high_res	High resolution tiff image was created.	
    --min_qual_mean  <int> minimum mean quality score of a read
    --min_len  <int> minimum length of a read
    --ns_max_p  <int> max percentage of Ns in read
    --realign   Flag to turn on realignment with ABRA
    --min_mapq  <int> Minimum mapping quality score
    --wing_length  <int> Number of bases on each side of sgRNA to view SNP 
    indir  input directory where intermediate result files (e.g. 
           plot image files) are, e.g ./align. 
    outdir  output directory, e.g. ./deliberables 
";
my %h;
GetOptions( \%h, 'ref=s', 'region=s', 'crispr=s', 'gene=s', 'cname=s', 'nocx',
    'high_res', 'min_qual_mean=i', 'min_len=i', 'ns_max_p=i', 'realign',
    'min_mapq=i', 'wing_length=i' );

die $usage if ( @ARGV != 2 );
my ( $indir, $outdir ) = @ARGV;
die "Missing required argument."
  if ( !$h{ref}
    or !$h{region}
    or !$h{gene}
    or !$h{crispr} );

my $ref  = $h{ref};
my $gene = $h{gene};
my ( $amp_chr, $amp_start, $amp_end, $amp_name, $amp_seq, $amp_strand ) =
  getTarget( $h{region} );
my ( $chr, $start, $end, $site_name, $seq, $strand, $hdr ) =
  getTarget( $h{crispr}, $h{cname} );
die "Incorrect crispr name $h{cname}.\n"
  if ( $h{cname} && $h{cname} ne $site_name );
$amp_start++;
$start++;

## set up Assets
my $sitedir = "$outdir/$site_name";
make_path($sitedir);
qx(cp $Bin/Assets/* $sitedir/Assets);

## find samples
my @samples = getSamples( $indir, $site_name );
my $rowsep = scalar(@samples) > 10 ? "</tr><tr>" : "";

## find processing errors
my $err_rows;   
foreach my $f ( sort glob("$indir/*.failed") ) {
    basename($f) =~ /(.*)\.failed$/;
    my $s = $1;
    open(my $erf, $f);
    my $err = <$erf>; chomp $err;
    close $erf;
    $err //= "Check log in $indir";
    $err_rows .= "<tr><td>$s</td><td>$err</td></tr>";
}

# create web page
my $page = "$sitedir/index.html";
open( my $fh, ">$page" ) or die $!;
my $rc_tog = getToggleLink("rc");         ## read count
my $pp_tog = getToggleLink( "pp", 1 );    ## preprocessing

my $plot_ext = $h{high_res} ? "tif" : "png";
my $hdr_snp_flag = $hdr ? 1 : 0;

print $fh "<!DOCTYPE html>
<html lang='en'>
	<head>
		<meta charset='utf-8'>
		<script src=Assets/crispr.js></script>
        <link href='Assets/crispr.css' type='text/css' rel='stylesheet' />
	<body>
		<h2>CRISPR Analysis Results</h2><p>
        <p><b>Gene: $gene</b><p>
        <table border=0><tr><td width=30></td><td>
		<table border=1 cellpadding=3 cellspacing=0 style='border-collapse:collapse' width=800>
			<tr align=center><th width=100>Region</th><th>Reference</th><th>Chr</th>
				<th>Start</th><th>End</th><th>Strand</th><th>Sequence</th>
				<th>Expected HDR Base Changes on + Strand</th></tr>
			<tr align=center><td>Amplicon</td><td>$ref</td><td>$amp_chr</td>
				<td>$amp_start</td><td>$amp_end</td><td>$amp_strand</td><td></td>
				<td></td></tr>
			<tr align=center><td>CRISPR Guide</td><td>$ref</td><td>$chr</td>
				<td>$start</td> <td>$end</td><td>$strand</td><td>$seq</td>
				<td>$hdr</td></tr>
		</table>
        </td></tr></table>
		<div id='high_res' style='display:none'>$h{high_res}</div>
		<p><b>Read Counts and Percentages at CRISPR Site:</b>$rc_tog
        <div class='descr'>
The count plot shows the number of reads (wild type, indel, and inframe indel) at the
 CRISPR site. The reads must span the sgRNA sequence region. Reads that only overlap with the sgRNA
 sequence partially are ignored. Wild type reads refer to reads that have no insertions or deletions
 (indel) in the sgRNA region. Indel reads have insertion and/or deletion of at least one base inside
 the sgRNA region. The deleted sequence can extend continously beyound the sgRNA region. Inframe
 indel reads are those indel reads that have net indel lengths as multiples of 3 and thus do not
 cause frame shift in translation.   
 <p>The percentage plot shows the percentage of read types with regard to total reads (WT reads +
 indel reads). 
 </div><p>
		<table><tr>
			<td><img src=Assets/$site_name.indelcnt.$plot_ext /></td>$rowsep
			<td><img src=Assets/$site_name.indelpct.$plot_ext /></td>
		</tr></table>
		</div>

		<!--select box for individual sample-->
		<p><b>Charts for Individual Sample</b>
		<select id='select1' onchange='showCharts(\"$site_name\",$hdr_snp_flag)'>
			<option value=''>Select a sample to view</option>
";

foreach my $s (@samples) {
    print $fh "<option value=\'$s\'>$s</option>";
}
print $fh "</select>
	<p id='charts'></p>
	<p><b>Preprocessing of Reads: </b>$pp_tog
    <div class='descr'>
      The first plot shows counting of reads at various stages: raw reads, quality reads, reads mapped
 to genome, and reads mapped to amplicon. 
      <br>The second plot shows the numbers of reads on different
 chromosomes. If reads are mapped to multiple chromosomes, that usually indicates non-specific
 amplifiction of the reads in the sample.
    </div><p>
	<table><tr>
		<td><img src=Assets/$site_name.readcnt.$plot_ext></td>$rowsep
		<td><img src=Assets/$site_name.readchr.$plot_ext></td>
	</tr></table>
";

if ( $err_rows ) {
    print $fh "<br>
          <table border=0><tr><td width=30></td><td>
             <table border=1 cellpadding=3 cellspacing=0 
                 style='border-collapse:collapse' width=400>
                 <tr><th>Sample</th><th>Processing Error</th></tr>
                 $err_rows
             </table>
          </td></tr></table>
    ";
}
print $fh "</div>";

## categories with each plot for individual sample
my %category_header = (
    "len" => "Allele Frequency at CRISPR Site",
    "cov" => "Amplicon Coverage",
    "ins" => "Insertion Distribution in Amplicon",
    "del" => "Deletion Distribution in Amplicon",
    "snp" => "SNP Frequency at CRISPR Site (Not all positions are on same read)",
	"hdr.snp" =>"SNP Frequency in HDR region (All positions are on same read)"
);

my @cats = ( "cov", "ins", "del", "len", "snp" );
push(@cats, "hdr.snp") if $hdr; 

my %des = getDescriptions();
 
foreach my $cat (@cats) {
    my $tab = getCategoryTable( $cat, $plot_ext );
    my $tog = getToggleLink( $cat, 1 );
    print $fh "<p><b>$category_header{$cat}:</b>$tog
   <div class='descr'>$des{$cat}</div><br> 
$tab</div>\n\n";
}

## HDR chart
if ($hdr) {
    my $hdr_tog = getToggleLink( "hdr", 1 );
    print $fh "
	<p><b>Homology Directed Repair Rates: </b>$hdr_tog
    <div class='descr'>
This plot compares the HDR rates across all samples. Read seqences in HDR/sgRNA region
 are categorized into four types: Non-Oligo, Partial, Edited, Perfect. The rate of
 perfect repair is labelled in the plot bars if it's greater than 0.1%. 
    </div><p>
        <table border=0><tr><td width=30></td><td>
		<table border=0>
        <tr><td>Non-Oligo: None of the intended base changes occurs, regardless of indel.</td></tr>
        <tr><td>Partial Oligo: Some but not all intended base changes occur, and no indel.</td></tr>
        <tr><td>Edited Oligo: One or more intended base changes occur, and there is indel.</td></tr>
		<tr><td>Perfect Oligo: All intended base changes occur, but no indel.
 Percentage value of perfect oligo is shown inside the bar.</td></tr>
		<tr>
			<td><img src=Assets/$site_name.hdr.$plot_ext /></td>$rowsep
		</tr>
		</table>
        </td></tr></table>
	</div>
";
}

## Allele alignment view
my $tog = getToggleLink( "cvxp", 1 );
if ( !$h{nocx} ) {
    print $fh "<p><b>Alignment of Indel Alleles:</b>$tog
       <table border=0><tr><td width=30></td><td>
       <table border=0 cellpadding=3 cellspacing=0 style='border-collapse:collapse'>
	      <tr><td><a href=${site_name}_cx1.html>Alleles with indel rate &ge; 1%</a></td></tr>
	      <tr><td><a href=${site_name}_cx0.html>All alleles</a></td></tr>
       </table>
       </td></tr></table>
       </div>
    ";
}

## Analysis parameters
$tog = getToggleLink( "param", 1 ); 
my $realign = $h{realign}? "Y" : "N";
print $fh "<p><b>Parameters Used in Analysis:</b>$tog
    <table border=0><tr><td width=30></td><td>
    <table border=1 cellpadding=3 cellspacing=0 style='border-collapse:collapse'>
        <tr><th>Parameter</th><th>Value</th></tr>
        <tr><td>Minimum mean quality score of read</td><td align=center>$h{min_qual_mean}</td></tr>
        <tr><td>Minimum length of read</td><td align=center>$h{min_len}</td></tr>
        <tr><td>Maximum percentage of non-called base N in read</td><td align=center>$h{ns_max_p}</td></tr>
        <tr><td>Minimum mapping quality score of read</td><td align=center>$h{min_mapq}</td></tr>
        <tr><td>Perform ABRA realignment after initial BWA alignment</td><td align=center>$realign</td></tr>
        <tr><td>Number of bases on each side of guide sequence to view SNP</td><td align=center>$h{wing_length}</td></tr>
    </table>
	</td></tr></table>
  </div>
";

## Spreadsheet data
$tog = getToggleLink( "data", 1 );
print $fh "<p><b>Spreadsheet Data:</b>$tog
    <div class='descr'>Most of the plots were drawn based on data in these spreadsheets:</div><p>
    <table border=0><tr><td width=30></td><td>
	<table border=0 cellpadding=3 cellspacing=0 style='border-collapse:collapse'>
		<tr><td><a href=Assets/${site_name}_cnt.xlsx>Read stats</a></td></tr>
		<tr><td><a href=Assets/${site_name}_pct.xlsx>Indel summary</a></td></tr>
		<tr><td><a href=Assets/${site_name}_len.xlsx>Allele data</a></td></tr>
		<tr><td><a href=Assets/${site_name}_snp.xlsx>SNP data (Not all positions are on same read)</a></td></tr>
";

if ($hdr) {
    print $fh
      "<tr><td><a href=Assets/${site_name}_hdr.snp.xlsx>SNP data (All positions are on same read)</a></td></tr>
      <tr><td><a href=Assets/${site_name}_hdr.xlsx>HDR data</a></td></tr>";
}

print $fh "</table>
     </td></tr></table>
   </div>
 </body></html>";
close $fh;

## return a category's html table of all samples
# input: extension of plots, like len.png for length distribution plot
sub getCategoryTable {
    my ( $cat, $plot_ext ) = @_;
    my $i     = 0;
    my $CELLS = $cat eq "snp" ? 1 : 2;    # number of cells per row
    my $tab   = "<table border=0>";
    foreach my $s (@samples) {
        my $img = "$sitedir/Assets/$s.$site_name.$cat.$plot_ext";
        next if !-f $img;
        if ( $i % $CELLS == 0 ) {
            $tab .= "</tr>" if ($i);
            $tab .= "<tr>";
        }

        $tab .= "<td><img src=Assets/$s.$site_name.$cat.$plot_ext></td>";
        $i++;
    }
    $tab .= "</tr>" if ( $tab !~ /<\/tr>$/ );
    $tab .= "</table>";
    return $tab;
}

# name is in 4th column
sub getTarget {
    my ( $bedfile, $name ) = @_;
    die "Cannot find $bedfile\n" if !-f $bedfile;

    ### Only the first coordinate entry is used.
    open( F, $bedfile ) or die "cannot open target file $bedfile\n";
    my $line;
    while ( $line = <F> ) {
        next if ( $line =~ /^\#/ or $line !~ /\w/ );
        chomp $line;
        my @a = split( /\s+/, $line );
        if ( !$name or $a[3] eq $name ) {
            last;
        }
    }
    close F;

    return split( /\s+/, $line );  # (chr, start, end, name, score, strand, hdr)
}

## find samples of this CRISPR site
sub getSamples {
    my ( $indir, $site_name ) = @_;
    my @samples;
    foreach my $f ( glob("$indir/*.$site_name.pct") ) {
        basename($f) =~ /(.*)\.${site_name}\.pct$/;
        push( @samples, $1 );
    }
    die "No sample data for $site_name\n" if !@samples;
    return sort @samples;
}

sub getToggleLink {
    my ( $sn, $hide ) = @_;

    # section name, like: pp --preprocessing
    # hide: 1 or 0

    my $fname = $hide ? "plus.jpg" : "minus.jpg";
    my $style = $hide ? "none"     : "block";

    # In IE, we have to specify no border.
    my $str =
      "<a href=\"javascript:hideshow(\'$sn.div\');toggleImg(\'$sn.img\')\">";
    $str .= "<img style='border:0;' src=Assets/$fname width=15 height=15 id=\'$sn.img\'></a>";
    $str .= "\n<div id=\"$sn.div\" style=\"display:$style\">";
    return $str;
}

sub getDescriptions {
   
    my $cov_des = "The plot shows the read depth in the amplicon range, with grey bar indicating the location of the CRISPR sgRNA region. Read depth at each position is the sum of reads aligned and reads with deletion at the position.";

    my $ins_des = "The plot shows the insertion rates across the amplicon range. Insertion rate is calculated as reads with insertion divided by read depth (aligned+deleted). If the insertion is caused by CRISPR, the insertion peak should overlap with the location of CRISRP site. If the peak is far away from the CRISPR site, the sgRNA sequence or coordinates provided may be incorrect, or the sample was swapped with another that has a different guide.";
	
    my $del_des = "The plot shows the deletion rates across the amplicon range. Deletion rate is calculated as reads with deletion divided by read depth (aligned+deleted). If the deletion is caused by CRISPR, the peak should overlap with the location of CRISRP site. If the peak is far away from the CRISPR site, the sgRNA sequence or coordinates provided may be incorrect, or the sample was swapped with another that has a different guide.";

    my $len_des = "The plot shows the locations and frequencies of the top-abundance indel alleles, and frequency of WT (non-indel) reads. The X-axis indicates the allele position and a net length change as a result of insertion and deletion. WT read has indel length of 0. If allele position is p, for insertion, the inserted bases occur between p and p+1; for deletion, the deleted bases range from p to (p + indel length - 1).

<p>In control sample where no CRISPR is introduced, there is often no significant number of indel reads. Without several indel alleles, the WT bar will look awefully wide in the plot. In order to maintain similar bar width comparable to other samples, sham alleles of zero reads are added to the plot and labeled like \"any:+n\" and \"any:-n\" in X-axis.";
 
    my $snp_des = "The plot shows the point mutation rates in and around a CRISPR site. The X-axis shows the position and reference base on positive strand; Y-axis shows the percentage of reads with the mutant bases. SNP rate is calculated as reads with point mutations divided by total aligned reads at the position. Reads with deletion at the position are not included in the total. The sgRNA sequence region is marked with a horizontal line. The number of bases on the sides of the guide to display is determined by the parameter wing_length in the conf.txt file. Please note that not every read is necessarily long enough to cover all the positions in the plot. Neighboring positions may not show on the same read."; 

    my $hdr_snp_des = "The chart is similar to the \"SNP Frequency at CRISPR Site\" chart. The differences are: (1) The coordinates are restricted to HDR/sgRNA region which covers all bases of intended HDR mutations and sgRNA region. (2) All positions in the chart are on same read. As a result, the SNP rates were deemed more accurate.";
    my %d = ( 'cov'=>$cov_des, 'ins'=>$ins_des, 'del'=>$del_des,
             'len'=>$len_des, 'snp'=>$snp_des, 'hdr.snp'=>$hdr_snp_des );
    return %d;
}
