unset module
## You may need to set PYTHONPATH to search for pysam module
## export PYTHONPATH=$PYTHONPATH:/path/to/pysam-module (not including pysam in the path)

../../crispr.pl --conf conf.txt --amp_fasta amplicon.fa --crispr site.bed \
	--sitemap sample.site \
	--fastqmap sample.fastq --amp_frame 1 --verbose
