# CRISPR-DAV: CRISPR NGS Data Analysis and Visualization Pipeline 

## Introduction

CRISPR-DAV is a pipeline to analyze amplicon-based NGS data of CRISPR clones in a high throughput manner. In the pipeline, BWA and ABRA are used for small and large indel detection. Results are presented in a comprehensive set of charts and interactive alignment view.

## Installing and running the pipeline

The pipeline can be installed via a docker container or the traditional physical approach. Please see [Install_and_Run](Install_and_Run.md) for instructions.


## Results

Results are available in 'deliverables' directory. Each subdirectory is for a CRISPR site. The index.html in the subdirectory is the HTML report, which looks like this:

![](images/resultpage.png?raw=true)


### Below are the descriptions for the result sections:

#### 1. Gene: 
Brief description about the amplicon and CRISPR target.
	
#### 2. Read Counts and Percentages at CRISPR Site:
The Count plot shows the number of wild type, indel, and inframe indel reads at the CRISPR site. The reads must span the sgRNA guide sequence region. Wild type reads have no indel in this region. Indel reads have at least one insertion or deletion base inside the sgRNA region. Inframe indel reads are part of the indel reads, but their indel length are multiples of 3 and thus do not cause frame shift in translation.   

The Percentage plot shows the percentage of read types with regard to total reads, i.e. WT reads + indel reads. 

The +/- circle image can be clicked to open or close the section.

![](images/percent.png?raw=true)


#### 3. Charts for Individual Sample. 
The allows to show charts of a particular sample together using a dropdown menu.

#### 4. Preprocessing of Reads
The first plot shows counting of reads at various stages: raw reads, filtered reads, reads mapped to genome, reads mapped to amplicon. The 2nd plot shows the numbers of reads on different chromosomes.

![](images/filtering.png?raw=true)

#### 5. Amplicon coverage: 
The plots show the read depth in the amplicon range, with grey bar indicating the location of the CRISPR sgRNA region. 

<div style="width:450px; height=300px">
![](images/coverage.png?raw=true)
</div>

#### 6. Insertion Distributions in Amplicon: 
The plot show the insertion rates across the amplicon range. If the insertion is caused by CRISPR, the insertion peak should overlap with the location of CRISRP site.

<div style="width:450px; height=300px">
![](images/insertion_survey.png?raw=true)
</div>

#### 7. Deletion Distributions in Amplicon: 
The plot show the deletion rates across the amplicon range. if the deletion is caused by CRISPR, the peak should overlap with the location of CRISRP site.

<div style="width:450px; height=300px">
![](images/deletion_survey.png?raw=true)
</div>

#### 8. Allele Frequencies at CRISPR Site: 
The plot shows the locations and frequencies of top alleles, and frequency of WT reads. This help to understand how the CRISPR affects sister chromosomes in a diploid genome.

In control sample where no CRISPR is introduced, there is often no significant number of indel reads. Without many alleles, the WT bar will look awefully wide in its plot. In order to maintain slim bar width comparable to other samples, sham alleles of zero reads but with label like "any:+n" and "any:-n" are added to plot.

<div style="width:450px; height=300px">
![](images/allele.png?raw=true)
</div>

#### 9. SNP Frequencies at CRISPR Site: 
The plot shows the point mutation rates in and around a CRISPR site. The X axis has the position and reference base on positive strand; the bars indicate the mutant bases. sgRNA sequence region is marked with a horizontal line. The number of bases on the sides of the sgRNA is determined by wing_length in the conf.txt file. In the chart below, it can be seen that the Homology-Directed Repair (HDR) clearly introduced expected mutations as indicated in the Gene Table. 

![](images/snp.png?raw=true)


#### 9. Homology Directed Repair (HDR) Rates: 
This plot compares the HDR rates across all samples. Oligos were categorized into 4 types. Their fractions and total reads were indicated. If HDR base changes are not specified in CRISPR bed file (site.bed), this section will not shows up. 

![](images/hdr.png?raw=true)

#### 10. Visual Alignment of Indel Alleles: 
This is an interactive alignment view of the sequences of sgRNA guide, WT, and indel alleles in the gene. The view is enabled with Canvas Xpress (http://canvasxpress.org/html/index.html). The bars can be zoomed and moved to the left or right. Only the coding sequence (CDS) is shown. If sgRNA sequence has intronic bases, they will not be drawn, causing the shown length of sgRNA sequence shorter than the original. Likewise, if some indel bases are inside intron, they will not be shown in the indel bars. Deletion is shown as a arc line connecting intact bases. Insertion is shown as a little tick mark between two bases. 

This section appears only when (1) refGene parameter is specified in conf.txt and the gene is found in the refGene file; or (2) amplicon is used as reference in lieu of genome, and codon_start is supplied.

![](images/allele_view.png?raw=true)

#### 11. Parameters Used in Analysis:
This shows the parameters used for read filtering and realignment.

#### 12. Spreadsheet data: 
This section presents the data in Excel files for download. 
