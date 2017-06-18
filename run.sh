# example to start the pipeline
## You may need to set PYTHONPATH to search for pysam module
## export PYTHONPATH=$PYTHONPATH:/path/to/pysam-module 
## You may need to set PERL5LIB path to search for perl modules
## export PERL5LIB=$PERL5LIB:/path/to/perl-module
unset module
genome=genomex
./crispr.pl --conf conf.txt --region amplicon.bed --crispr site.bed \
	--sitemap sample.site --fastqmap fastq.list --genome $genome
