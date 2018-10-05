## Create plot of read counts on chromosomes
## Author: X. Wang

suppressMessages(library(ggplot2))
suppressMessages(library(naturalsort))
options(scipen=999)
Sys.setlocale("LC_ALL", "en_US.UTF-8")

args <- commandArgs(trailingOnly=FALSE)
script.name <- sub("--file=", "", args[grep("--file=",args)])
script.path <- dirname(script.name)
source(file.path(script.path, "func.R"))

args <- commandArgs(trailingOnly=TRUE)
if(length(args) < 1) {
  args <- c("--help")
}

## Help section
if("--help" %in% args) {
  exit(cat( script.name, "
      Arguments:
      --inf=chr count tsv file with header: Sample, Chromosome, ReadCount. Required.
      --high_res=1 or 0. 1-create high resolution .tif image. 0-create png file.
      --outf=output image file. Required.
      --help    Print this message
  "))
}

## Parse arguments (we expect the form --arg=value)
parseArgs <- function(x) strsplit(sub("^--", "", x), "=")
argsDF <- as.data.frame(do.call("rbind", parseArgs(args)))
argsL <- as.list(as.character(argsDF$V2))
names(argsL) <- argsDF$V1
if ( is.null(argsL$inf) | is.null(argsL$outf) ) {
    exit("Missing required argument")
}

## set the output file name and path
infile<- argsL$inf
outfile <- argsL$outf
high_res = ifelse(is.null(argsL$high_res), 0, as.numeric(argsL$high_res))

if (file.exists(infile)==FALSE) exit(paste("Could not find", infile))

## create the plot
dat <- read.table(file=infile, sep="\t", header=TRUE, stringsAsFactors=FALSE)

dat$Chromosome<- factor(dat$Chromosome, levels=naturalsort(unique(dat$Chromosome)))
p<-ggplot(dat, aes(x=Chromosome, y=ReadCount, fill=Sample)) +
	labs(x="Chromosome", y="Number of reads", title="Reads Mapped on Chromosomes") + 
	theme_bw() + customize_title_axis(angle=90) 

if ( nrow(dat) > 0 ) {
	p <- p + geom_bar(stat='identity', position=position_dodge(), width=0.5)
} else {
	write(paste("Warning: No data in input file", infile), stderr())
	p <- p + scale_y_continuous(limits=c(0, 1000)) + 
		annotate(geom='text', x=1, y=500, label="No reads mapped to reference",
			size=5, family='Times', fontface="bold") +
		theme(axis.text.x = element_blank())
}

# number of samples
n <- length(unique(dat$Sample))
if ( high_res ) {
	h<-4
	w<-ifelse(n>5, h*1.25+(n-5)*0.3, h*1.25)
	tiff(filename=outfile, width=w, height=h, units='in', res=1200)
} else {
	h<-400
	w<-ifelse(n>5, 100*n, 550)
	max_w=1000
	w <- ifelse(w>max_w, max_w, w)
	png(filename=outfile, height=h, width=w)
}

print(p)
invisible(dev.off())
