export PYTHONPATH=$PYTHONPATH:/home/wangx112/lib/python2.7/site-packages
unset module
/home/wangx112/dev/crispr-dav/crispr.pl --conf conf.txt --amp_fasta amp.fa --crispr site.bed \
	--sitemap sample.site \
	--fastqmap sample.fastq --amp_frame 1 --verbose
