## Example script to run the pipeline
## If there is problem loading pysam module, set PYTHONPATH accordingly, e.g. 
#export PYTHONPATH=$HOME/lib/python2.7/site-packages:$PYTHONPATH 

## If there is problem loading Perl modules., set PERL5LIB accordingly.
#export PERL5LIB=$HOME/perlmod/lib/perl5:$PERL5LIB
../../crispr.pl --conf conf.txt --region amplicon.bed --crispr site.bed \
	--sitemap sample.site --fastqmap fastq.list --genome genomex 

