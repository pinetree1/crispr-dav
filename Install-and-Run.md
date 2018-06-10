<center><h3>Installing and Running CRISPR-DAV Pipeline</h3></center>

<br>
The CRISPR-DAV pipeline can be run via a docker container or a physical installation.

### I. Running via docker container

The docker repository for CRISPR-DAV is called [**pinetree1/crispr-dav**](https://hub.docker.com/r/pinetree1/crispr-dav/). It's based on the official Fedora image at Docker Hub, and has included the pipeline and prerequisite tools. No physical installation of them is required but you need to be able to run docker on your system.

The pipeline includes three examples:

(1) Example 1: uses a standard reference as genome. You'll prepare a few input files: amplicon.bed, conf.txt, fastq.list, sample.site, site.bed, fastq files, and run.sh. 

(2) Example 1_a: uses the same fastq and reference as the example1. The conf.txt defaults to the one in the crispr-dav pipeline root path. Instead of several files (amplicon.bed, site.bed etc), only a single tab-delimited text file (e.g. samplesheet.txt) is prepared. The crispr-dav/prepare_run.pl will generate these small files. Compared to example 1, this example simplifies the preparation work. For example, it does not require you to write down the coordinates of sgRNA sequences.

(3) Example 2: uses a fastq sequence as genome. You'll also prepare a set of files similar to Example 1.

Here are steps to test run example1. Running other examples is quite similar. You may replace /Users/xyz/temp with your own absolute path in the following commands. 

(1) Start the container interactively and mount a path of host to the container:

        docker run -it -v /Users/xyz/temp:/Users/xyz/temp pinetree1/crispr-dav 

The docker image takes a few minutes to start up for the first time. This command also mounts /Users/xyz/temp from the host to /Users/xyz/temp in the container. Inside the container, the pipeline is in /crispr-dav.

(2) After starting up, at the container prompt, go to example1 directory:

        cd /crispr-dav/Examples/example1

(3) Start the pipeline:
      
        sh run.sh

(4) When the pipeline is finished, move the results to the shared directory in container:

        mv deliverables /Users/xyz/temp

(5) Exit from the container:

        exit

(6) On the host, open a browser to view the report, index.html, in /Users/xyz/temp/deliverables/GENEX_CR1.

For example1_a, first run './prepare_run.pl samplesheet.txt' and then cd to the resulting amplicon directory to run the run.sh.

The general steps for analyzing your own project via the docker are similar. You'll need to prepare samplesheet (or a set of input files: conf.txt, amplicon.bed, site.bed, sample.site, fastq.list, and run.sh, similar to those in the examples); and prepare reference genome or amplicon sequence. The important thing is to share your data directories with the container when starting the container. For example, assuming that there are 3 directories on the host related to your project:

    /Users/xyz/temp/project: contains the input files.
      
    /Users/xyz/temp/rawfastq: contains the fastq files.
      
    /Users/xyz/temp/genome: contains the genome files.

You'll mount these directories to the container (using the same paths for convenience):

    docker run -it -v /Users/xyz/temp/project:/Users/xyz/temp/project \
    -v /Users/xyz/temp/rawfastq:/Users/xyz/temp/rawfastq \
    -v /Users/xyz/temp/genome:/Users/xyz/temp/genome \
    pinetree1/crispr-dav 

In this case, since these directories are under the same parent, you could actually just mount the parent:

    docker run -it -v /Users/xyz/temp:/Users/xyz/temp pinetree1/crispr-dav
    
    cd /Users/xyz/temp/project

Then edit conf.txt, fastq.list, and run.sh to reflect the paths in the container. 

Start the pipeline by: sh run.sh. The results will be present in the project directory of the container and the host. 


### II. Running via a physical installation

The pipeline runs on Linux and MacOS. The installation on Linux is a bit simpler than on MacOS. 

#### 1. Clone the repository
  
    git clone https://github.com/pinetree1/crispr-dav.git

In the resulting crispr-dav directory, all the Perl programs (\*.pl) use this line to invoke the perl in your environment: \#!/usr/bin/env perl. The path of env on your system may differ. If so, the path should be changed accordingly in all \*.pl files in crispr-dav directory.

#### 2. Install prerequisite tools    

The pipeline utilizes a set of tools, most of which are common in bioinformatics field. These include Perl and Python modules, R, and NGS tools.  

**A. Perl modules**

The following modules are required but may not be present in default perl install.  

    Config::Tiny
    Excel::Writer::XLSX
    Spreadsheet::XLSX (Required only if the sample sheet is an Excel file rather than tab-delimited text file)
    JSON

Run this command to check whether they are already installed: 

    perl -e "use <module>", e.g. perl -e "use Config::Tiny"

If there is no output, the module is already installed. Error message will show up if it's not installed.

If you have root privilege, installing a perl module could be simple:

    sudo cpanm <module>, e.g. cpanm Config::Tiny
 
If you prefer to install modules as a non-root user, these steps show how to install Config::Tiny into local directory $HOME/perlmod:   

    wget http://search.cpan.org/CPAN/authors/id/R/RS/RSAVAGE/Config-Tiny-2.23.tgz 
    tar xvfz Config-Tiny-2.23.tgz
    cd Config-Tiny-2.23
    perl Makefile.PL INSTALL_BASE=$HOME/perlmod
    make
    make install

The modules can be found in CPAN. Install the other modules similarly. Keep in mind that if they have dependencies which are not already installed on your system, you will need to install them as well.

If a module is installed globally by root, it is already in @INC which has paths that perl searches for a module. 

But if the module is installed in a local path, you'll need to add the path to @INC by setting PERL5LIB: 

	export PERL5LIB=$HOME/perlmod/lib/perl5:$PERL5LIB


**B. NGS tools**

- ABRA: Assembly Based ReAligner. Recommended version: [0.97]( https://github.com/mozack/abra/releases/download/v0.97/abra-0.97-SNAPSHOT-jar-with-dependencies.jar). **Java 1.7 or later is needed to run the realigner.**

    Example installation by non-root user on Linux:
    
	    mkdir -p $HOME/app/ABRA
	    cd $HOME/app/ABRA
	    wget https://github.com/mozack/abra/releases/download/v0.97/abra-0.97-SNAPSHOT-jar-with-dependencies.jar (Pre-built jar for 64-bit Linux)
	    
    On MacOS, the jar file has to be re-built. The steps are a bit complex:
    
        First, clone and make Google sparsehash temporarily:
            
            mkdir ~/temp
            cd ~/temp
            git clone https://github.com/sparsehash/sparsehash.git
            cd sparsehash
            ./configure
            make
        
        Second, download ABRA source file:
        
            cd ~/temp
            wget https://github.com/mozack/abra/archive/v0.97.tar.gz
            tar xvfz v0.97.tar.gz
            cd abra-0.97/src/main/c
            
            Now replace the abra's sparsehash with the new one:
            
            mv sparsehash sparsehash.old
            ln -s ~/temp/sparsehash/src/sparsehash
            
            Still in abra-0.97/src/main/c, create links to java library files(jni.h and jni_md.h):
            
            which java: this shows /usr/bin/java, for example.
            ls -l /usr/bin/java: shows it links to /System/Library/Frameworks/JavaVM.framework/Versions/Current/Commands/Java. Then the two header files can be found in "Current" directory.
            ln -s /System/Library/Frameworks/JavaVM.framework/Versions/Current/Headers/jni.h
            ln -s /System/Library/Frameworks/JavaVM.framework/Versions/Current/Headers/jni_md.h
            
        Third, build the jar file. You'll need Maven and g++.
        
            which mvn: shows the mvn path. Otherwise install it from Apache.
            cd ~/temp/abra-0.97
            make
            mv target/abra-0.97-SNAPSHOT-jar-with-dependencies.jar $HOME/app/ABRA
            
	
- BWA: Burrows-Wheeler Aligner. **Make sure your version supports "bwa mem -M" command, and bwa must be put in PATH for use by ABRA.** Recommended version: [0.7.15](https://sourceforge.net/projects/bio-bwa/files/bwa-0.7.15.tar.bz2/download). 

    Example install by non-root user:

    	cd $HOME/app
	    wget https://sourceforge.net/projects/bio-bwa/files/bwa-0.7.15.tar.bz2/download --no-check-certificate -O bwa-0.7.15.tar.bz2
	    tar xvfj bwa-0.7.15.tar.bz2
	    cd bwa-0.7.15
	    make
    
    Be sure to put executable 'bwa' in your PATH, for example, by adding this line to $HOME/.bashrc assuming you are using bash:
    
	    export PATH=$HOME/app/bwa-0.7.15:$PATH
 	
    
- Samtools: Recommended version: [1.3.1](https://sourceforge.net/projects/samtools/files/samtools/1.3.1/samtools-1.3.1.tar.bz2/download). Older version of samtools is OK. 

    Example install by non-root user:

	    cd $HOME/app
	    wget https://sourceforge.net/projects/samtools/files/samtools/1.3.1/samtools-1.3.1.tar.bz2/download --no-check-certificate -O samtools-1.3.1.tar.bz2
	    tar xvfj samtools-1.3.1.tar.bz2
	    ./configure
	    make

- Bedtools2: **Make sure your version supports -F option in 'bedtools intersect' command.** Recommended version: [2.25.0]( https://github.com/arq5x/bedtools2/releases/download/v2.25.0/bedtools-2.25.0.tar.gz)

    Example install by non-root user:

	    cd $HOME/app
	    wget https://github.com/arq5x/bedtools2/releases/download/v2.25.0/bedtools-2.25.0.tar.gz 
	    tar xvfz bedtools-2.25.0.tar.gz
	    cd bedtools2
	    make

- PRINSEQ: Recommended version: [0.20.4](https://sourceforge.net/projects/prinseq/files/standalone/prinseq-lite-0.20.4.tar.gz/download). **Be sure to make the program prinseq-lite.pl executable:** 

    Example install by non-root user:
        
	    cd $HOME/app
	    wget https://sourceforge.net/projects/prinseq/files/standalone/prinseq-lite-0.20.4.tar.gz/download --no-check-certificate -O prinseq-lite-0.20.4.tar.gz
	    tar xvfz prinseq-lite-0.20.4.tar.gz
	    cd prinseq-lite-0.20.4
	    chmod +x prinseq-lite.pl

- FLASH: Recommended version: [2](https://github.com/dstreett/FLASH2), for merging paired-end reads.

    Example install by non-root user:
    
	    cd $HOME/app
	    git clone https://github.com/dstreett/FLASH2.git
	    cd FLASH2
	    make

**C. R packages**

- R packages: ggplot2, reshape2, naturalsort

    To check whether a package is already installed, at R prompt, type for example:
    
        >libarary(ggplot2). Absence of output means it is already installed.
    
    To install the packages, after starting R, type:

        >install.packages("ggplot2")
        >install.packages("reshape2")  
        >install.packages("naturalsort")

    If you get permission errors, check with your admin. 
    
    If you have to install R in a local directory, here are example steps:
        
        cd $HOME/app
        wget https://cran.r-project.org/src/base/R-3/R-3.2.1.tar.gz
        tar xvfz R-3.2.1.tar.gz
        cd R-3.2.1
        ./configure
        make
        
        Then install the packages as stated above.
        
**D. Python program** 

Required: Pysamstats https://github.com/alimanfoo/pysamstats 

To install it as root, the simple steps are:

    sudo pip install pysam==0.8.4
    sudo pip install pysamstats==0.24.3
    
    These modules will be installed in system-wide location. No export of PYTHONPATH is needed.
    

To install it in home directory, you may try these steps:

- ***Install prerequisite pysam module:***

        pip install --install-option="--prefix=$HOME" pysam==0.8.4

This would install pysam in $HOME/lib/python2.7/site-packages, assuming your Python version is 2.7 (The 'lib' could be lib64, depending on system).

Then make pysam module searchable:

		export PYTHONPATH=$PYTHONPATH:$HOME/lib/python2.7/site-packages

- ***Install pysamstats:***

        pip install --install-option="--prefix=$HOME" pysamstats==0.24.3

This would install pysamstats module in the same place as pysam module, and install an executable script $HOME/bin/pysamstats.

Check whether the modules can be loaded:

        $ python
        >>>import pysam
        >>>import pysamstats
        >>>exit()

If there is no output, the installation is successful. 

You should add the export command to the pipeline's run.sh script, if the modules are installed by non-root user.

On Linux system, you may drop the version numbers (e.g, ==0.8.4) to install the most recent versions. However, on MacOS (at least X El Capitan), the recent verions (0.11.x) of pysam seem problematic, but the pair of pysam 0.8.4 and pysamstats 0.24.3 works alright.

#### 3. Test-run Examples 

CRISPR-DAV includes two examples in Examples directory. The example1 uses a genome as reference, whereas example2 uses an amplicon sequence as reference. Example3 simpifies run preparation, as described above. The procedure to run the pipelines is similar in the examples.
 
        cd crispr-dav/Examples/example1

        Edit the conf.txt and run.sh accordingly. Remember to add commands of setting PERL5LIB and PYTHONPATH in run.sh if the Perl and Python modules were installed locally.  

        Start the pipeline: sh run.sh. This shell script invokes the main program crispr.pl which starts the pipeline.

The pipeline would create these directories: 

- align: contains the intermediate files. They can be removed once the HTML report is produced. For description of the file types, please check the README file in the directory.  

    Make sure not to put your source fastq files in this directory. They could be overwritten there.

- deliverables: contains the results. The HTML report file index.html is in a subdirectory.

### III. Preparing input files for and running your pipeline

- **Fastq files:**

These are the raw fastq files. They must be gzipped with file extension .gz. Put the fastq files in a directory outside the pipeline's output directory. Don't put them inside the pipeline's "align" directory, as they could get overwritten.

- **Reference files:** 

An amplicon sequence or a genome can be used as a reference. If an amplicon sequence is used for reference, all you need is a **fasta** file containing sequence ID and the sequence.
 
If a genome is used as reference, you'll prepare a fasta file, BWA index, and refGene coordinate files 

A. Prepare fasta file:

For example, to parepare human genome hg19, download the chromosome sequence files from UCSC browser, uncompress and combine them into one file, e.g. hg19.fa.

B. Create Fasta index: 

    samtools faidx hg19.fa

C. Create bwa index: 
    
    bwa index hg19.fa

D. Download refGene table:

Go to UCSC Genome Broser (http://genome.ucsc.edu/cgi-bin/hgBlat), click Tools and select TableBrowser. Then make these selections:

    Assembly: hg19
    Group: Genes and Gene Predictions
    Track: RefSeq Genes
    Table: refGene
    Region: Genome
    Output format: all fields from selected table. 
    
The downloaded tab-delimited file should have these columns: bin, name, chrom, strand, txStart, txEnd, cdsStart, cdsEnd, exonStarts, exonEnds,...

- **conf.txt:**

This file specifies the reference genomes, software paths, and pipeline parameters. Usually this file rarely changes once it is set. Modify the conf.txt in the script directory according to your settings.

- **setup_env.sh:**

This file specifies the Perl/Python modules and PATH variable. Modify the setup_env.sh in the script directory according to your environment. This file need change only once. If you can access these modules and bwa without setting these paths, then this file is not needed.

- **samplesheet.txt:**

The samplesheet will be used to prepare the inputs for the pipeline. Use the samplesheet.txt.template or Examples/example1_a/samplesheet.txt as example. Information for this file include Gene symbol, Genome, Amplicon range, Guide Sequence, HDR Intended Bases, Sample Name, Sample ID, Project ID, and Fastq Path. All coordinates are 1-based in this file. Place the samplesheet.txt in a project directory. The last two columns are optional. 


To run pipeline, do these:

    prepare_run.pl samplesheet.txt    (or add -f <path> option to specify fastq directory)
    
    Then go to each resulting amplicon directory and start the pipeline: sh run.sh. It's convenient to run it in the background and store any output in a log file, like this: sh run.sh &> r.log &
    
See Test-run Examples for instructions to find results.
    
### Description of files created by prepare_run.pl script:
    

- **amplicon.bed:**

A tab-delimited text file with 6 columns for: chr, start, end, genesymbol, refseq_accession, strand. Only one amplicon is allowed. The start and end are 0-based, conforming to BED format. Genesymbol should have no space. Refseq_accession must match the value in the "name" field (2nd column) in genome's refGene table for the gene.

- **site.bed:**

A tab-delimited text file with 6 or 7 columns for: chr, start, end, crispr_name, sgRNA_sequence, strand, HDR_new_bases_and_positions. This file can contain multiple rows, but crispr_name and sgRNA_sequence must be unique. All the CRISPR sites must belong to the same amplicon. Start and end are 0-based. 

The 7th field is optional. If HDR is performed, enter expected base changes in the field. 

HDR format: <Pos1><NewBase1>,<Pos2><NewBase2>,... The bases are desired new bases on ***positive strand***, e.g.101900208C,101900229G,101900232C,101900235A. No space. The positions are 1-based.


- **sample.site:**

This file controls what samples to be analyzed. It's a tab-delimited text file with 2 or more columns for: sample name, sgRNA_sequence1, sgRNA_sequence2, ... 

- **fastq.list:**

A tab-delimited text file with 2 or 3 columns for: sample name, read1 file, optional read2 file. Fastq files must be gzipped with .gz extension. The sample name must match what's in sample.site. 

- **conf.txt:**

This file is copied over from the crispr-dav root directory.

- **run.sh:**

This is the wrapper script for starting the pipeline.

- **project.conf:**

The file captures some major information in the project. It is not required for the pipeline itself. It's intended for use by downstream processing if any.


### IV. Troubleshooting

- **Errors before pipeline starts:**

These are errors related to prerequisite tools and data inputs. For example, if a required tool or module is not found, there will be error message indicating the issue. You may try setting PERL5LIB and PYTHONPATH if the module is installed. If an input file used space instead of the required tab as separator, the pipeline would report error of missing columns.  
 
- **Errors during pipeline:**

  There are several log files per sample. Check the README in 'align' directory for descriptions. For example, if the installed Bedtools version does not support "bedtools insert -F", there will be error messages in the <sample>.log file. 
