# example to start the pipeline
## You may need to set PYTHONPATH to search for pysam module
## export PYTHONPATH=$PYTHONPATH:/path/to/pysam-module (not including pysam in the path)
unset module
genome=genomex
./crispr.pl --conf conf.txt --region amplicon.bed --crispr site.bed \
	--sitemap sample.site --fastqmap sample.fastq --genome $genome
