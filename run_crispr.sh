# example to start the pipeline
unset module
genome=genomex
./crispr.pl --conf conf.txt --region amplicon.bed --crispr site.bed \
	--sitemap sample.site --fastqmap sample.fastq --genome $genome
