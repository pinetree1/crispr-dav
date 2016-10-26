# example to start the pipeline
genome="hg19"
~/dev/crispr/crispr.pl --conf conf.txt --region amplicon.bed --crispr site.bed \
	--sitemap sample.site --filemap samples.txt --genome $genome --verbose --sge 
