#export PYTHONPATH=$PYTHONPATH:$HOME/lib/python2.7/site-packages
unset module
../../crispr.pl --conf conf.txt --amp_fasta amp.fa --crispr site.bed \
	--sitemap sample.site --fastqmap fastq.list --codon_start 1 

