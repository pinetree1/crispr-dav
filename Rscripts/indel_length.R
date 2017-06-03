## Create a plot of indel length vs count
## Author: X. Wang
suppressMessages(library(ggplot2))
options(scipen=999)

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
      --inf=input indel detail file for single sample, e.g, <sample>.<site>.len. Required.
      --sample=sample name. No space. Required.
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
if ( is.null(argsL$inf) | is.null(argsL$outf) | is.null(argsL$sample) ) {
    exit("Missing required argument")
}

## set the output file name and path
infile<- argsL$inf
outfile <- argsL$outf 
high_res = ifelse(is.null(argsL$high_res), 0, as.numeric(argsL$high_res))
sample<- argsL$sample

if (file.exists(infile)==FALSE) exit(paste("Could not find", infile))

dat <- read.table(file=infile, sep="\t", header=TRUE, stringsAsFactors=FALSE )

NO_DATA = FALSE 
if (nrow(dat)==0) {
	write(paste("Warning: No data in indel length input file:", infile), stderr())
	NO_DATA = TRUE 
}

## Add dummy data if number of unique indel lengths < 11 
vec=c(0)
for (x in 1:5) { vec <- c(vec, x, -x) }
for ( len in vec ) {
	indLens = unique(dat$IndelLength)
	if (length(indLens) > 11) 
		break

	if ( len %in% indLens == FALSE ) {
		dat[nrow(dat)+1, ] <- rep(0, 9) 
		dat[nrow(dat), 'IndelLength'] <- len
	} 		
}

ag <- aggregate(dat$ReadCount, by=list(dat$IndelLength), FUN=sum)
colnames(ag)<- c('bin', 'freq')
rows <- nrow(ag)

## select max topN rows of high frequencies
topN = 20
n = ifelse(rows >=topN, topN, rows)	
ag <- ag[with(ag, order(freq, decreasing=TRUE)), ][(1:n),]	
ag$Type <- ifelse(ag$bin==0, "WT", ifelse(ag$bin>0, "Insertion", "Deletion"))

# number of indel lengths
if ( high_res ) {
	h<-4
	w<-ifelse(n>40, 0.13*n, h*1.25)
	tiff(filename=outfile, width=w, height=h, units='in', res=1200)
} else {
	h<-400
	w<- ifelse(n>40, 13*n, h*1.25)
	png(filename=outfile, height=h, width=w)
}

on.exit(dev.off())

p<-ggplot(ag, aes(x=factor(bin), y=freq, fill=factor(Type, levels=c("Deletion", "WT", "Insertion")))) +
	geom_bar(stat="identity", position="dodge", width=0.2) + 
	scale_fill_manual(values=c("WT"="#e74c3c", "Deletion"="#229954", "Insertion"="#2e86c1")) +
	labs(x="Indel Length", y="Reads", title=paste("Sample:", sample)) +
	theme(legend.title=element_blank(), legend.text=element_text(size=13), 
		legend.position='bottom',legend.direction='horizontal' ) +
	customize_title_axis(angle=90)

if ( NO_DATA==TRUE ) {
	p <- p + scale_y_continuous(limits=c(0,500)) + 
		annotate(geom='text', x=6, y=250, label="No reads at CRISPR site", 
		family='Times', fontface="bold", size=5)
} 

print(p)
