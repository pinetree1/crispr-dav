# example to start the pipeline
genome=genomex
./crispr.pl --conf conf.txt --region amplicon.bed --crispr site.bed \
	--sitemap sample.site --fastqmap sample.fastq --genome $genome
