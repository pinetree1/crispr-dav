## ## Create plot of read counts on different chromosomes
suppressMessages(library(ggplot2))
suppressMessages(library(naturalsort))
options(scipen=999)

args <- commandArgs(trailingOnly=FALSE)
script.name <- sub("--file=", "", args[grep("--file=",args)])
script.path <- dirname(script.name)
source(file.path(script.path, "func.R"))

args <- commandArgs(trailingOnly=TRUE)

if (length(args) != 2) {
	cat(paste("Usage:", script.name, "{chr count file} {output image png file}\n"))
	cat("\tThe input file is a tsv file with header: Sample, Chromosome, ReadCount\n")
	q()
}

## set the output file name and path
infile<-args[1]
outfile <- args[2]
if (file.exists(infile)==FALSE) exit(paste("Could not find", infile))

## create the plot
dat <- read.table(file=infile, sep="\t", header=TRUE, stringsAsFactors=FALSE)
dat$Chromosome<- factor(dat$Chromosome, levels=naturalsort(unique(dat$Chromosome)))

p<-ggplot(dat, aes(x=Chromosome, y=ReadCount, fill=Sample)) +
	geom_bar(stat='identity', position=position_dodge()) +
	labs(x="Chromosome", y="Number of reads", title="Reads Mapped on Chromosomes") + 
	theme_bw() + customize_title_axis(angle=90) 

# number of samples
n <- nlevels(dat$Sample)
h<-500
w<-ifelse(n>5, 100*n, h)
w <- w * length(unique(dat$Chr)) / 25

png(filename=outfile, height=h, width=w)
print(p)
invisible(dev.off())
