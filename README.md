# CRISPR Analysis Pipeline 

## Installation 

##### Clone the CRISPR pipeline repository:

git clone git@biogit.pri.bms.com:wangx112/crispr.git 

##### Install required tools: 

(1) Install tools

	Details are in Install/required_tools.txt.  
	The tools can be installed in appropriate directory as non-root user. If some tools are already installed in your system, you don't need to re-install. 

	Here are the steps to install all the tools in crispr base directory
 
	cd crispr 
	mkdir app  
	cd app 
	sh ../Install/install_app.sh 

(2) Install perl and python modules

	The perl modules etc must be installed as root.
	sh ../Install/install_mod.sh 

##### Prepare a genome  

(1) Prepare fasta file. For example, to parepare human genome hg19, download the chromosome sequence files from UCSC browser, combine them (excluding the haplotype and chrUn) into one file, hg19.fa.

(2) Create bwa index for it: bwa index hg19.fa 

(3) Download refGene table. From UCSC TableBrowser page (Tools->TableBrowser), select assembly hg19, group: Genes and Gene Predictions, track: RefSeq Genes, table: refGene.   

## Run pipeline

An example run is in the Example directory. The fastq directory contains fastq files that must be gzipped. The hg19 directory contains the genome files. You'll need prepare genome files only once as described above. The hg19.fa.fai will be automatically created by pipeline. 

In the 'run' directory, there are 5 files to prepare:

	conf.txt: Use the conf.txt in crispr.pl script directory as template, modify the paths and settings according to your installation and project requirement.  

	amplicon.bed: a tab-delimited text file with 6 columns: chr, start, end, genesymbol, refseq_accession, strand. Only one amplicon is allowed in a pipeline. 1-based start and end.
 
	site.bed: a tab-delimited text file with 7 columns: chr, start, end, crispr_name, sgRNA_sequence, strand, HDR_new_bases_and_positions. This file can contain multiple records, but crispr_name and sgRNA_sequence must be unique. 1-based start and end.

	samples.txt: a tab-delimited text file with 2 or 3 columns: sample name, read1 file, optional read 2 file.

	sample.site: a tab-delimited text file with 2 columns: sample name, sgRNA_sequence.

	None of the files should have column header.

	The script run_crispr.sh starts the pipeline: 
	sh run_script.sh &> r.log &

	This will create 2 directories: 

	align: this contains the intermediate files.  

	deliverables: this contain the results. Each Crispr name will have a sub-directory here, and contains index.html file for viewing the results. 
