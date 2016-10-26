## Create plot of read counts at different processing stages
suppressMessages(library(ggplot2))
library(reshape2)
options(scipen=999)

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

remove_dup = ifelse(is.null(argsL$rmd), 'N', argsL$rmd)
if (!remove_dup %in% c('Y', 'N')) {
	exit("--rmd value can only be 'Y' or 'N'")
}


## create the plot
readTypes <- c("RawReads", "QualityReads", "MappedReads", "UniqueReads", "RegionReads")
labels<- c("Raw Reads", "Quality Reads", "Mapped Reads", "Unique Reads", "Amplicon Reads")
if ( remove_dup == 'N' ) {
	readTypes = readTypes[readTypes != "UniqueReads"]
	labels = labels[labels != "Unique Reads"]
}

dat <- read.table(file=infile, sep="\t", header=TRUE)
if (nrow(dat)==0) exit("No data in input file")
dat.m <- melt(dat, id.vars="Sample", measure.vars=readTypes)

# number of samples
n <- nlevels(dat$Sample)
h<-500
w<-h
if ( n > 10 ) {
	w<-50*n
}

png(filename=outfile, height=h, width=w)


ggplot(dat.m, aes(x=Sample, y=value, fill=variable)) + 
geom_bar(stat='identity', position=position_dodge()) +
labs(x="Sample", y="Number of reads", title="Reads at Preprocessing Stages") + 
scale_fill_discrete(breaks=readTypes, labels=labels) +
guides(fill=guide_legend(title=NULL)) +
theme_bw() + customize_title_axis(angle=45) 

invisible(dev.off())
