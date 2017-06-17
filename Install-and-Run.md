<center><h3>Installing and Running CRISPR-DAV Pipeline</h3></center>

<br>
The CRISPR-DAV pipeline can be run via a docker container or a physical installation.

### I. Running via docker container

The docker repository for CRISPR-DAV is called [**pinetree1/crispr-dav**](https://hub.docker.com/r/pinetree1/crispr-dav/). It has the pipeline and prerequisite tools. No physical installation is required but you need to be able to run docker on your system. 

The pipeline includes two example projects. Here are steps to test run example1. Running example2 is quite similar.  

(1) Start the container interactively and mount a path of host to the container:

        docker run -it -v /Users/xyz/temp:/Users/xyz/temp pinetree1/crispr-dav bash

The docker image is about 1GB, and takes a few minutes to start up. This command mounts /Users/xyz/temp in the host to /Users/xyz/temp in the container. Inside the container, the pipeline's path is /opt/crispr-dav.

(2) After starting up, at the container prompt, go to example1 directory:

        cd /opt/crispr-dav/Examples/example1

(3) Start the pipeline:
      
        sh run.sh

(4) When the pipeline is finished, move the results to the shared directory in container:

        mv deliverables /Users/xyz/temp

(5) Exit from the container:

        exit

(6) On the host, open a browser to view the report index.html file in /Users/xyz/temp/deliverables/GENEX_CR1.


The general steps for analyzing your own project via the docker are simlar. The important thing is to share your data directories with the container. For example, assuming that there are 3 directories on the host related to your project:

      /Users/xyz/temp/project: contains the input files (amplicon.bed, conf.txt, fastq.list, run.sh, sample.site, and site.bed).
      
      /Users/xyz/temp/rawfastq: contains the fastq files.
      
      /Users/xyz/temp/genome: contains the genome files.

You'll mount these directories to the container using the same paths:

    docker run -it -v /Users/xyz/temp/project:/Users/xyz/temp/project \
      -v /Users/xyz/temp/rawfastq:/Users/xyz/temp/rawfastq \
      -v /Users/xyz/temp/genome:/Users/xyz/temp/genome \
      pinetree1/crispr-dav bash

    cd /Users/xyz/temp/project

Then edit conf.txt, fastq.list, and run.sh to reflect the paths in the container. Start the pipeline by: sh run.sh. The results will be present in the project directory of the container and the host.


### II. Running via a physical installation

#### 1. Clone the repository
  
        git clone https://github.com/pinetree1/crispr-dav.git

In the resulting crispr-dav directory, all the Perl programs (\*.pl) use this line to invoke the perl in your environment: \#!/usr/bin/env perl. The path of env on your system may differ. If so, the path should be changed accordingly in all \*.pl files in crispr-dav directory.

#### 2. Install prerequisite tools    

The pipeline utilizes a set of tools, most of which are common in bioinformatics field. These include Perl and Python modules, R, and NGS tools.  

**A. Perl modules **

The following modules are required but may not be present in default perl install.  

    Config::Tiny
    Excel::Writer::XLSX
    JSON

Run this command to check whether they are already installed: 

    perl -e "use <module>", e.g. perl -e "use Config::Tiny"

If there is no output, the module is already installed. Error message will show up if it's not installed.

If you have root privilege, installing a perl module could be simple:

    cpanm <module>, e.g. cpanm Config::Tiny
 
If you prefer to install modules as a non-root user, these steps show how to install Config::Tiny into local directory $HOME/perlmod:   

    wget http://search.cpan.org/CPAN/authors/id/R/RS/RSAVAGE/Config-Tiny-2.23.tgz 
    tar xvfz Config-Tiny-2.23.tgz
    cd Config-Tiny-2.23
    perl Makefile.PL INSTALL_BASE=$HOME/perlmod
    make
    make install

If a module is installed globally by root, it is already in @INC which has paths that perl searches for a module. 

But if the module is installed in a local path, you'll need to add the path to @INC by setting PERL5LIB: export PERL5LIB=\$HOME/perlmod:$PERL5LIB
. You may add the line to the pipeline script run.sh in crispr-dav directory.

**B. NGS tools**

- BWA: Burrows-Wheeler Aligner. **Make sure your version supports "bwa mem -M" command.** Recommended version: [0.7.15](https://sourceforge.net/projects/bio-bwa/files/bwa-0.7.15.tar.bz2/download)

- Samtools: Recommended version: [1.3.1](https://sourceforge.net/projects/samtools/files/samtools/1.3.1/samtools-1.3.1.tar.bz2/download). Older version of samtools is OK. 

- Bedtools2: **Make sure your version supports -F option in 'bedtools intersect' command.** Recommended version: [2.25.0]( https://github.com/arq5x/bedtools2/releases/download/v2.25.0/bedtools-2.25.0.tar.gz)

- PRINSEQ: Recommended version: [0.20.4](https://sourceforge.net/projects/prinseq/files/standalone/prinseq-lite-0.20.4.tar.gz/download). **Be sure to make the program prinseq-lite.pl executable:** 

        chmod +x prinseq-lite.pl

- ABRA: Assembly Based ReAligner. Recommended version: [0.97]( https://github.com/mozack/abra/releases/download/v0.97/abra-0.97-SNAPSHOT-jar-with-dependencies.jar). **Java 1.7 or later is needed to run the realigner.**

**C. R packages**

- R packages: ggplot2, reshape2, naturalsort

To install the packages, after starting R, type:

        >install.packages("ggplot2")
        >install.packages("reshape2")
        >install.packages("naturalsort")

If you get permission errors, check with your admin or install R in a local directory.

**D. Python program ** 

Required: Pysamstats https://github.com/alimanfoo/pysamstats 

To install it as root, check the web site for instructions. 

To install it in home directory, you may try these steps:

- ***Install prerequisite pysam module:***

        pip install --install-option="--prefix=$HOME" pysam==0.8.4

This would install pysam in $HOME/lib/python2.7/site-packages, assuming your Python version is 2.7.

- ***Install pysamstats:***

        git clone git://github.com/alimanfoo/pysamstats.git
        cd pysamstats
        python setup.py install --prefix=$HOME

This would install an executable script pysamstats in $HOME/bin and pysamstats module in $HOME/lib/python2.7/site-packages.

Check whether the modules can be loaded:

        $ python
        >>>import pysam
        >>>import pysamstats
        >>>exit()

If there is no output, the installation is successful. Otherwise, try to include the python library path to PYTHONPATH and add it to the pipeline's run.sh script, for example:
    
        export PYTHONPATH=$PYTHONPATH:$HOME/lib/python2.7/site-packages


#### 3. Test run 

The pipeline can be started using the shell script template run.sh, which invokes the main program crispr.pl. Modify the files referred in run.sh to suit your project.    
    
For test run, CRISPR-DAV includes two examples in Examples directory. The example1 uses a genome as reference, whereas example2 uses an amplicon sequence as reference. The procedure to run the pipelines is similar in the examples.
 
        cd crispr-dav/Examples/example1
        Edit the conf.txt and run.sh accordingly. 
        Start the pipeline: sh run.sh

The pipeline would create these directories: 

- align: contains the intermediate files. They can be removed once the HTML report is produced. For description of the file types, please check the README file in the directory.  

    Make sure not to put your source fastq files in this directory. They could be overwritten there.

- deliverables: contains the results. The HTML report file index.html is in a subdirectory.
