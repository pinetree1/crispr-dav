# install application tools

dir=`pwd`
opt="--no-check-certificate -q"

## BWA
url=https://sourceforge.net/projects/bio-bwa/files/bwa-0.7.15.tar.bz2/download
(wget $url $opt && tar xfj bwa-0.7.15.tar.bz2 && cd bwa-0.7.15 && make) &> bwa.log

## samtools
url=https://sourceforge.net/projects/samtools/files/samtools/1.3.1/samtools-1.3.1.tar.bz2/download
(cd $dir && wget $url $opt && tar xfj samtools-1.3.1.tar.bz2 && cd samtools-1.3.1 && make) &> samtool.log &
 
## prinseq
url=https://sourceforge.net/projects/prinseq/files/standalone/prinseq-lite-0.20.4.tar.gz/download
(cd $dir && wget $url $opt && tar xfz prinseq-lite-0.20.4.tar.gz && chmod +x prinseq-lite-0.20.4/prinseq-lite.pl) &>prinseq.log &

## Picard
url=https://sourceforge.net/projects/picard/files/picard-tools/1.119/picard-tools-1.119.zip/download
(cd $dir && wget $url $opt && unzip picard-tools-1.119.zip) &>picard.log

## R
url=https://cran.r-project.org/src/base/R-3/R-3.2.1.tar.gz
(cd $dir && wget $url $opt && tar xfz R-3.2.1.tar.gz && cd R-3.2.1 && ./configure && make) &> r.log 

# Then install packages: ggplot2, reshape2, and naturalsort

## bedtools. Downloading could be problematic on aws
url=https://github.com/arq5x/bedtools2/releases/download/v2.25.0/bedtools-2.25.0.tar.gz
(cd $dir && wget $url $opt -O bedtools-2.25.0.tar.gz && tar xfz bedtools-2.25.0.tar.gz && cd bedtools2 && make) &>bedtool.log

## ABRA. Downloading on AWS could be problematic.
url=https://github.com/mozack/abra/releases/download/v0.97/abra-0.97-SNAPSHOT-jar-with-dependencies.jar
(cd $dir && wget $url $opt -O abra-0.97-SNAPSHOT-jar-with-dependencies.jar) &>abra.log

cd $dir
if [ ! -s "bwa-0.7.15/bwa" ]; then 
	echo "Failed to install bwa"
else
	echo "Successfully installed bwa"
fi 

if [ ! -s "samtools-1.3.1/samtools" ]; then
	echo "Failed to install samtools"
else
	echo "Successfully installed samtools"
fi

if [ ! -s "prinseq-lite-0.20.4/prinseq-lite.pl" ]; then
	echo "Failed to install prinseq"
else
	echo "Successfully installed prinseq"
fi

if [ ! -s "picard-tools-1.119/MarkDuplicates.jar" ]; then 
	echo "Failed to install Picard"
else
	echo "Successfully installed Picard"
fi

if [ ! -s "R-3.2.1/bin/R" ]; then
	echo "Failed to install R"
else
	echo "Successfully installed R"
fi
echo "You'll need also to instal R packages(ggplot2 and naturalsort), if R is successfully installed."
 
if [ ! -s "bedtools-2.25.0.tar.gz" ]; then 
	echo "Failed to download bedtools"
else
	echo "Successfully installed bedtools"
fi

if [ ! -s "abra-0.97-SNAPSHOT-jar-with-dependencies.jar" ]; then
	echo "Failed to download ABRA"
else
	echo "Successfully installed ABRA"
fi
