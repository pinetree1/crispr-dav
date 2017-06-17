<center><h2>CRISPR-DAV: CRISPR NGS Data Analysis and Visualization Pipeline</h2></center>
<br>

### Introduction

CRISPR-DAV is a pipeline to analyze amplicon-based NGS data of CRISPR clones in a high throughput manner. In the pipeline, BWA alignment and ABRA realignment are performed to detect insertion and deletion. The realignment with ABRA has improved detection of large indels. Results are presented in a comprehensive set of charts and interactive alignment view.

### Installing and running the pipeline

The pipeline can be run via a docker container or a physical install. Please see [Install-and-Run](Install-and-Run.md) for instructions.


### Results

Results are presented in an HTML report, which looks like this:

![](images/resultpage.png?raw=true)

<br>

The various sections are described below:

#### 1. Gene: 

Brief information about the amplicon and CRISPR target.
	
#### 2. Read Counts and Percentages at CRISPR Site:

The Count plot shows the number of reads (wild type, indel, and inframe indel) at the CRISPR site. The reads must span the sgRNA sequence region. Wild type reads have no indel in this region. Indel reads have insertion and/or deletion overlapping and potentially extending beyound the sgRNA region. Inframe indel reads are part of the indel reads, but their indel lengths are multiples of 3 and thus do not cause frame shift in translation.   

The Percentage plot shows the percentage of read types with regard to total reads (WT reads + indel reads). 

![](images/percent.png?raw=true)


#### 3. Charts for Individual Sample:

This section shows a group of charts for a particular sample chosen from a dropdown menu. 

#### 4. Preprocessing of Reads:

The first plot shows counting of reads at various stages: raw reads, filtered reads, reads mapped to genome, and reads mapped to amplicon. The second plot shows the numbers of reads on different chromosomes.

If a sample has no reads in the source fastq files or after filtering, the sample will not be drawn in the charts, but a message table would appear below the charts to indicate the issue.

![](images/filtering.png?raw=true)

#### 5. Amplicon coverage: 

The plots show the read depth curve in the amplicon range, with grey bar indicating the location of the CRISPR sgRNA region. 

<div style="width:450px; height=300px">
![](images/coverage.png?raw=true)
</div>

#### 6. Insertion Distribution in Amplicon: 

The plots show the insertion rates across the amplicon range. If the insertion is caused by CRISPR, the insertion peak should overlap with the location of CRISRP site.

<div style="width:450px; height=300px">
![](images/insertion_survey.png?raw=true)
</div>

#### 7. Deletion Distribution in Amplicon: 

The plots show the deletion rates across the amplicon range. if the deletion is caused by CRISPR, the peak should overlap with the location of CRISRP site.

<div style="width:450px; height=300px">
![](images/deletion_survey.png?raw=true)
</div>

#### 8. Allele Frequency at CRISPR Site: 

The plots show the locations and frequencies of the top-abundance alleles, and frequency of WT reads. This helps to understand how CRISPR affects sister chromosomes in a diploid genome.

In control sample where no CRISPR is introduced, there is often no significant number of indel reads. Without many indel alleles, the WT bar will look awefully wide in the plot. In order to maintain slim bar width comparable to other samples, sham alleles of zero reads are added to the plot and labeled like "any:+n" and "any:-n" in x-axis.

<div style="width:450px; height=300px">
![](images/allele.png?raw=true)
</div>

#### 9. SNP Frequency at CRISPR Site: 

The plots show the point mutation rates in and around a CRISPR site. The X axis has the position and reference base on positive strand; the bars indicate the mutant bases. The sgRNA sequence region is marked with a horizontal line. The number of bases on the sides of the sgRNA is determined by the parameter wing_length in the conf.txt file. In the chart below, it can be seen that the Homology-Directed Repair (HDR) clearly introduced expected mutations as indicated in the Gene Table. 

![](images/snp.png?raw=true)


#### 10. Homology Directed Repair (HDR) Rates: 

This plot compares the HDR rates across all samples. Oligo nucleotide seqences in HDR region are categorized into 4 types. Their fractions and total reads are indicated. The rate of perfect oligo is labelled. If HDR base changes are not specified in CRISPR bed file (site.bed), the section will not appear. 

![](images/hdr.png?raw=true)

#### 11. Visual Alignment of Indel Alleles: 

This is an interactive alignment view of the sequences of sgRNA guide, WT, and indel alleles in the gene. The frequencies of WT, deletion and insert reads are shown. The view is enabled with Canvas Xpress (http://canvasxpress.org/html/index.html). The bars can be zoomed in and out, and moved to the left and right. Only the coding sequence (CDS) is drawn in the bars. If the sgRNA sequence has intronic bases, these bases will not be drawn, causing the sgRNA sequence look shorter than the original. Likewise, if some indel bases are inside intron, they will not be drawn. Deletion is shown as a arc line connecting intact bases. Insertion is shown as a tick mark between two bases. However, the inserted bases are not shown.

This section appears only when (1) the parameter refGene is specified in conf.txt and the gene of interest can be found in the refGene file; or (2) an amplicon sequence is used as reference in lieu of genome, and codon_start option is supplied.

![](images/allele_view.png?raw=true)

#### 12. Parameters Used in Analysis:

This shows the parameters used for read filtering, realignment, and SNP plot region.

#### 13. Spreadsheet data: 

This section presents the results in Excel files for download. 
