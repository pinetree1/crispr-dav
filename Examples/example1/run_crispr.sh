## Example script to run the pipeline
## If there is problem loading pysam module, set PYTHONPATH to search for pysam module
## export PYTHONPATH=$PYTHONPATH:<parent directory of pysam module> 
unset module
../../crispr.pl --conf conf.txt --region amplicon.bed --crispr site.bed \
	--sitemap sample.site --fastqmap sample.fastq --genome genomex 

## You may add --sge option if your system is set up for SGE.
