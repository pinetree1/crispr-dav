# install application tools

dir=`pwd`
opt="--no-check-certificate -q"
echo Current directory: $dir

## BWA
echo Installing bwa ...
url=https://sourceforge.net/projects/bio-bwa/files/bwa-0.7.15.tar.bz2/download
(wget $url $opt && tar xfj bwa-0.7.15.tar.bz2 && cd bwa-0.7.15 && make) &> bwa.log

if [ ! -s "bwa-0.7.15/bwa" ]; then 
	echo "Failed to install bwa"
else
	echo "Successfully installed bwa"
fi 

## samtools
echo Installing samtools ...
url=https://sourceforge.net/projects/samtools/files/samtools/1.3.1/samtools-1.3.1.tar.bz2/download
(cd $dir && wget $url $opt && tar xfj samtools-1.3.1.tar.bz2 && cd samtools-1.3.1 && make) &> samtool.log 

if [ ! -s "samtools-1.3.1/samtools" ]; then
	echo "Failed to install samtools"
else
	echo "Successfully installed samtools"
fi

## prinseq
echo Installing prinseq ...
url=https://sourceforge.net/projects/prinseq/files/standalone/prinseq-lite-0.20.4.tar.gz/download
(cd $dir && wget $url $opt && tar xfz prinseq-lite-0.20.4.tar.gz && chmod +x prinseq-lite-0.20.4/prinseq-lite.pl) &>prinseq.log 

if [ ! -s "prinseq-lite-0.20.4/prinseq-lite.pl" ]; then
	echo "Failed to install prinseq"
else
	echo "Successfully installed prinseq"
fi

## R
echo Installing R ...
url=https://cran.r-project.org/src/base/R-3/R-3.2.1.tar.gz
(cd $dir && wget $url $opt && tar xfz R-3.2.1.tar.gz && cd R-3.2.1 && ./configure && make) &> r.log 

if [ ! -s "R-3.2.1/bin/R" ]; then
	echo "Failed to install R"
else
	echo "Successfully installed R"
fi
echo "You'll need also to instal R packages(ggplot2 and naturalsort), if R is successfully installed."
# Then manually install packages: ggplot2, and naturalsort

## bedtools. Downloading could be problematic on aws
echo Installing bedtools ...
url=https://github.com/arq5x/bedtools2/releases/download/v2.25.0/bedtools-2.25.0.tar.gz
(cd $dir && wget $url $opt -O bedtools-2.25.0.tar.gz && tar xfz bedtools-2.25.0.tar.gz && cd bedtools2 && make) &>bedtool.log

if [ ! -s "bedtools-2.25.0.tar.gz" ]; then 
	echo "Failed to download bedtools."
else
	echo "Successfully installed bedtools"
fi

## ABRA. Downloading on AWS could be problematic.
echo Installing ABRA ...
url=https://github.com/mozack/abra/releases/download/v0.97/abra-0.97-SNAPSHOT-jar-with-dependencies.jar
(cd $dir && wget $url $opt -O abra-0.97-SNAPSHOT-jar-with-dependencies.jar) &>abra.log

if [ ! -s "abra-0.97-SNAPSHOT-jar-with-dependencies.jar" ]; then
	echo "Failed to download ABRA"
else
	echo "Successfully installed ABRA"
fi
