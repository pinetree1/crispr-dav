# install application tools

dir=`pwd`
opt=--no-check-certificate

## BWA
url=https://sourceforge.net/projects/bio-bwa/files/bwa-0.7.15.tar.bz2/download
wget $url $opt && tar xfj bwa-0.7.15.tar.bz2 && cd bwa-0.7.15 && make

## samtools
url=https://sourceforge.net/projects/samtools/files/samtools/1.3.1/samtools-1.3.1.tar.bz2/download
cd $dir && wget $url $opt && tar xfj samtools-1.3.1.tar.bz2 && cd samtools-1.3.1 && make
 
## prinseq
url=https://sourceforge.net/projects/prinseq/files/standalone/prinseq-lite-0.20.4.tar.gz/download
cd $dir && wget $url $opt && tar xfz prinseq-lite-0.20.4.tar.gz

## Picard
url=https://sourceforge.net/projects/picard/files/picard-tools/1.119/picard-tools-1.119.zip/download
cd $dir && wget $url $opt && unzip picard-tools-1.119.zip

## R
url=https://cran.r-project.org/src/base/R-3/R-3.2.1.tar.gz
cd $dir && wget $url && tar xfz R-3.2.1.tar.gz && cd R-3.2.1 && ./configure && make 
# Then install packages: ggplot2, reshape2, and naturalsort

## bedtools. Downloading could be problematic on aws
url=https://github.com/arq5x/bedtools2/releases/download/v2.25.0/bedtools-2.25.0.tar.gz
cd $dir && wget $url -O bedtools-2.26.0.tar.gz && tar xfz bedtools-2.26.0.tar.gz && cd bedtools2 && make

## ABRA. Downloading on AWS could be problematic.
url=https://github.com/mozack/abra/releases/download/v0.97/abra-0.97-SNAPSHOT-jar-with-dependencies.jar
cd $dir && wget $url -O abra-0.97-SNAPSHOT-jar-with-dependencies.jar

cd $dir
if [ ! -s "bedtools-2.25.0.tar.gz" ]; then 
	echo "Failed to download bedtools"
fi

if [ ! -s "abra-0.97-SNAPSHOT-jar-with-dependencies.jar" ]; then
	echo "Failed to download ABRA"
fi

