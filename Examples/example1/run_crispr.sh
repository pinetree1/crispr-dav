## You may need to set PYTHONPATH to search for pysam module
## export PYTHONPATH=$PYTHONPATH:/path/to/pysam-module
unset module
../../crispr.pl --conf conf.txt --region amplicon.bed --crispr site.bed \
	--sitemap sample.site --fastqmap sample.fastq --verbose --genome genomex 

## You may add --sge option if your system is set up for SGE.
