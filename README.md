# CRISPR Analysis Pipeline 

## Installation 

1. Create a repository by git clone:

git clone http://biogit.pri.bms.com/wangx112/crispr_pub.git

2. Install required tools: check Install/requirement.txt

3. Prepare a genome of interest. 

(1) Prepare fasta file. For example, to parepare human genome hg19, download the chromosome sequence files from UCSC browser, combine them (excluding the haplotype and chrUn) into one file, hg19.fa.

(2) Create bwa index for it: bwa index hg19.fa 

(3) Download refGene table. From UCSC TableBrowser page (Tools->TableBrowser), select assembly hg19, group: Genes and Gene Predictions, track: RefSeq Genes, table: refGene.   

## Run pipeline

An example run is in the Example directory. The fastq directory contains fastq files. The hg19 directory is where the genome files are. You'll need prepare those only once as described above. The hg19.fa.fai will be automatically created by pipeline. 

In the 'run' directory, there are 5 files to prepare:

	conf.txt: This is a copy of conf.txt from the crispr.pl script directory. Modified the settings to reflect your installation environment. 

	amplicon.bed: a tab-delimited text file with 6 columns: chr, start, end, genesymbol, refseq_accession, strand. Only one amplicon is allowed in a pipeline.
 
	site.bed: a tab-delimited text file with 7 columns: chr, start, end, crispr_name, sgRNA_sequence, strand, HDR_new_bases_and_positions. This file can contain multiple records, but crispr_name and sgRNA_sequence must be unique.

	file.map: a tab-delimited text file with 2 or 3 columns: sample name, read1 file, optional read 2 file

	sample.site: a tab-delimited text file with 2 columns: sample name, sgRNA_sequence 

	The script run_crispr.sh starts the pipeline.

	sh run_script.sh &> r.log &

	This will create 2 directories: 

	align: this contains the intermediate files.  

	deliverables: this contain the results. Each Crispr name will have a sub-directory here, and contains index.html file for viewing the results. 
