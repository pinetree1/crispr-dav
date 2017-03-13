# CRISPR Analysis Pipeline 

## Installation 

### 1. Clone the CRISPR pipeline repository:

In a directory where you want the pipeline to be installed, type:

    git clone https://biogit.pri.bms.com/wangx112/crispr.git 

### 2. Install required tools: 

#### A. Install tools

The following tools are required. See details are in Install/required_tools.txt.  

    bwa, samtools 1.x, bedtools2, prinseq, ABRA, R, R packages ggplots and naturalsort.
    
The tools can be installed in appropriate directory as non-root user or root. If some tools are already installed in your system, you may not need to re-install. 

 
    cd <app directory> 

	sh <crispr directory>/Install/install_app.sh 
	
	If an app failed to install, you need to install it manually. Check the details in the script for steps.
	
	After R is installed, you need to start R and install two packages manually:
	    <app directory>/R-3.2.1/bin/R
	    >install.packages("naturalsort")
	    >install.packages("ggplot2")

#### B. Install perl and python modules

The required modules are listed in <crispr directory>/Install/install_mod.sh.
    
Install them as **root**:

	sh <crispr directory>/Install/install_mod.sh 
	
This should install the modules in system-wide locations so that non-root user can access. 

To check whether the perl modules are installed, run this as regular user:

    sh <crispr directory>/Install/check_perlmod.pl

If there is no output, the installation was successful.

To check whether python modules are accessible, do this as regular user:

    $python
    >>>import pysam
    >>>import pysamstats
    >>>exit()

Again, if there is no output, the installation is successful.
	

### 3. Prepare a genome  

In the Examples/example1 provided in the pipeline package, a test genome is already prepared. To run the examples, you can skip this step. 

Below are general steps for preparing a genome: 

#### A. Prepare fasta file:
For example, to parepare human genome hg19, download the chromosome sequence files from UCSC browser, combine them (excluding the haplotype and chrUn) into one file, hg19.fa.

#### B. Create bwa index:
For example, to create bwa index for hg19.fa:  	
	
	bwa index hg19.fa 

#### C. Download refGene table: 
Go to UCSC Genome Broser (http://genome.ucsc.edu/cgi-bin/hgBlat), then click on Tools and select TableBrowser. Select assembly hg19, group: Genes and Gene Predictions, track: RefSeq Genes, table: refGene. Download the file in plain text to the same directory as the genome file.

If the sequence of an amplicon is used as reference, only a fasta file needs to be created if the sequence is all in exons. See the 'Run pipeline' section for more details.  An example is in Examples/example2 in the pipeline package.


## Run pipeline

There are two example runs in the "Examples" directory. 

### 1. example1: 
This example shows how to run the pipeline when a genome is used as reference. The genome is in exmaple1/genome directory. See the above on how to prepare a genome. In addition, there are several input files to prepare:

#### conf.txt: 
Use the conf.txt in crispr.pl script directory as template, modify the paths and settings according to your installation and project requirement.  

#### amplicon.bed: 
A tab-delimited text file with 6 columns: chr, start, end, genesymbol, refseq_accession, strand. Only one amplicon is allowed. The start and end are 1-based and inclusive. Genesymbol should have no space. Refseq_accession must match the "name" (2nd column) in genome's refGene table.  
 
#### site.bed: 
A tab-delimited text file with 7 columns: chr, start, end, crispr_name, sgRNA_sequence, strand, HDR_new_bases_and_positions. This file can contain multiple records, but crispr_name and sgRNA_sequence must be unique among the records. All the crisprs must belong to the same amplicon. Start and end are 1-based and inclusive.

#### sample.fastq: 
A tab-delimited text file with 2 or 3 columns: sample name, read1 file, optional read2 file. Fastq files must be gzipped with .gz extension.

#### sample.site: 
A tab-delimited text file with 2 or more columns: sample name, sgRNA_sequence. The sample name must match what's in sample.fastq. All samples listed in sample.site will be analyzed. 

None of the files should have column header.

#### To start the pipeline: 

    cd <crispr directory>/Examples/example1
    
    Edit conf.txt: change the paths to genome and applications accordingly.
    
    cp ../run_script.sh .

    Edit the script accordingly. If --sge option is added to the command line, the pipeline will submit jobs to SGE default queue, provided it's set up for your system. Without this option, jobs will be processed in serial fashion on local host. 

    Run the pipeline in background by issuing this command:

    sh run_script.sh &> r.log &

This will create 2 directories: 

* align: this contains the intermediate files.  

* deliverables: this contains the results. Each crispr name will have a sub-directory under it. The subdirectory contains index.html file for viewing the results. 

### 2. example2: 
This example shows how to run the pipeline when an amplicon sequence is used as reference. 

To use an amplicon sequence as reference, use --amp_fasta to specify an amplicon fasta file. The --genome option must not be used. The pipeline will create the bwa index of the amplicon sequence, and create the refGene equivalent table based on translation frame provided, assuming translation occurs on the positive strand and there is no intron in the amplicon sequence. Otherwise, then the refGene table must be pre-created and example1 should be followed. 

--amp_fasta: specify a reference sequence for the amplicon. The file must be a fasta file with an ID and only one sequence. 

--amp_frame: Translation starting position in the amplicon reference sequence. If the first codon starts at the first base, then the position is 1.

site.bed: the chromosome name must be the same as that in amplicon fasta file. The start and end positions mean the positions of a CRISPR guide sequence in the amplicon sequence.

All other files and steps are similar to those in example1.

## Results

Results are available in 'deliverables' directory. Each subdirectory is for a CRISPR site. Results for a CRISPR site are accessable via index.html in the subdirectory. The html page looks like this:

![](readme_images/resultpage.png?raw=true)


Below are the descriptions for the result sections:

#### 1. Gene: 
Brief description about the amplicon and CRISPR target.
	
#### 2. Read Counts and Percentages at CRISPR Site:
The Count plot shows the number of wild type, indel, and inframe reads at the CRISPR site. The reads must span the sgRNA region. Wild type reads have no indel in this region. Indel reads have at least one insertion or deletion base inside the sgRNA region. Inframe indel reads are part of the indel reads, but their indel length are multiples of 3 and thus do not cause frame shift in translation.   

The Percentage plot shows the percentage of read types out of total reads, i.e. WT reads + indel reads. Pct Inframe indel reads is the percentage of all inframe indel reads out of the total reads.

The +/- circle image can be clicked to open or close the section.

![](readme_images/percent.png?raw=true)


#### 3. Charts for individual sample. 
The allows to show charts of only one sample. 

#### 4. Amplicon coverage: 
The plots show the read depth in the amplicon range, with grey bar indicating the location of the CRISPR sgRNA region. The minimum depth at boundaries is shown. This value is set in the conf.txt file.

![](readme_images/coverage.png?raw=true)


#### 5. Insertion Location in Amplicon: 
The plots show the insertion rates across the amplicon range. When there is a significant percentage of insertion, the peak should overlap with the location of CRISRP site.

![](readme_images/insertion_survey.png?raw=true)


#### 6. Deletion Location in Amplicon: 
The plots show the deletion rates across the amplicon range. When there is a significant percentage of deletion, the peak should overlap with the location of CRISRP site.

![](readme_images/deletion_survey.png?raw=true)


#### 7. Indel Length at CRISPR site: 
Two plots are shown for each sample. The first plot does not include WT read count, in order to see the reads of insertion and deletion in higher scale when the reads are predominantly WT. The second plot includes WT. 

![](readme_images/indel_length.png?raw=true)


#### 8. SNP Locations around CRISPR site: 
In a plot, the X axis shows the position and reference base, the bars indicate the point mutation frequencies. sgRNA region is marked with a horizontal bar. The number of bases on the sides of the sgRNA is determined by wing_length in the conf.txt file.

![](readme_images/snp.png?raw=true)


#### 9. Homology Directed Repair (HDR) Rates: 
This section shows the HDR rates. Oligos were categorized into 4 types. The fractions and total reads were plotted. This section appears only when HDR base changes are specified in crispr bed file (site.bed). The desired new bases supplied must be on positive strand.

![](readme_images/hdr.png?raw=true)


#### 10. Visual Alignment of Indel Alleles: 
This section appears only when gene/cds/exon coordinates were provided via refGene parameter in conf.txt or in case of amplicon as reference the amp_frame option was supplied. The image was created with Canvas Xpress (http://canvasxpress.org/html/index.html). It shows insertion and deletion locations in the context of coding sequence (CDS) and sgRNA guide sequence. The bars can be zoomed in and out (by rolling middle mouse key), and moved to the left or right. If the shown guide sequence is not full length, that is because the missed bases happen to be in intronic region. Likewise, if some indel bases are inside intron, they will not be shown in the bars either. Deletion is shown as a curved line bridging intact bases. Insertion is shown as a little line between two bases.  

![](readme_images/allele_view.png?raw=true)


#### 11. Spreadsheet data: 
This section presents the data in Excel files for download. The plots in previous sections were generated using the spreadsheet data. 	
