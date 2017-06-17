## Example script to run the pipeline
## If there is problem loading pysam module, set PYTHONPATH accordingly, e.g. 
export PYTHONPATH=$PYTHONPATH:$HOME/lib/python2.7/site-packages 
unset module
../../crispr.pl --conf conf.txt --region amplicon.bed --crispr site.bed \
	--sitemap sample.site --fastqmap fastq.list --genome genomex 

