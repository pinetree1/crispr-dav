## Create plot of read counts at different processing stages
## Author: X. Wang
suppressMessages(library(ggplot2))
suppressMessages(library(naturalsort))
suppressMessages(library(reshape2))
options(scipen=999)
Sys.setlocale("LC_ALL", "en_US.UTF-8")

args <- commandArgs(trailingOnly=FALSE)
script.name <- sub("--file=", "", args[grep("--file=",args)])
script.path <- dirname(script.name)
source(file.path(script.path, "func.R"))

args <- commandArgs(trailingOnly=TRUE)
if (length(args) < 2) {
	args<- c("--help")
}

## Help section
if("--help" %in% args) {
  exit(cat( script.name, "
	Arguments:
	--inf=read count file. Required.
	--high_res=1 or 0. 1-create high resolution .tif image. 0-create png file.
	--outf=output png file. Required.
	--rmd=Y/N. Y-Duplicate is removed. N-Duplicate is not removed. Default: N.
	--help	Print this message	
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
infile<-argsL$inf;
outfile <- argsL$outf
if (file.exists(infile)==FALSE) exit(paste("Could not find", infile))
high_res = ifelse(is.null(argsL$high_res), 0, as.numeric(argsL$high_res))
remove_dup = ifelse(is.null(argsL$rmd), 'N', argsL$rmd)
if (!remove_dup %in% c('Y', 'N')) {
	exit("--rmd value can only be 'Y' or 'N'")
}

## create the plot
readTypes <- c("RawReads", "QualityReads", "MappedReads", "UniqueReads", "AmpliconReads")
labels<- c("Raw Reads", "Quality Reads", "Mapped Reads", "Unique Reads", "Amplicon Reads")
if ( remove_dup == 'N' ) {
	readTypes = readTypes[readTypes != "UniqueReads"]
	labels = labels[labels != "Unique Reads"]
}

dat <- read.table(file=infile, sep="\t", header=TRUE)

dat.m <- melt(dat, id.vars="Sample", measure.vars=readTypes)
dat.m$Sample<- factor(dat.m$Sample, levels=naturalsort(unique(dat.m$Sample)))

# number of samples
n <- nlevels(dat$Sample)
if ( high_res ) {
	h<-4
	w<-ifelse(n>5, h*1.25+(n-5)*0.3, h*1.25)
	tiff(filename=outfile, width=w, height=h, units='in', res=1200)
} else {
	h<-400
	w<- ifelse(n>10, 50*n, h)
	png(filename=outfile, height=h, width=w)
}

p <- ggplot(dat.m, aes(x=Sample, y=value, fill=variable)) + 
	labs(x="Sample", y="Number of reads", title="Reads at Preprocessing Stages") + 
	scale_fill_discrete(breaks=readTypes, labels=labels) +
	theme_bw() + customize_title_axis(angle=45) 

if (nrow(dat)>0) {
	p <- p + geom_bar(stat='identity', position=position_dodge(), width=0.5) +
		theme(legend.title=element_blank(),
			legend.text=element_text(face="bold", size=12))

} else {
	write(paste("Warning: No data in input file", infile), stderr())
	p <- p + scale_y_continuous(limits=c(0, 1000)) +
		annotate(geom='text', x=1, y=500, label="No reads in raw data",
			size=5, family='Times', fontface="bold") +
		theme(axis.text.x = element_blank())
}

print(p)
invisible(dev.off())
