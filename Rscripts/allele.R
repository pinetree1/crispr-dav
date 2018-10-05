## Create a plot of allele frequencyt
## Author: X. Wang
suppressMessages(library(ggplot2))
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
if (nrow(dat)==1 & dat$IndelStr[1]=="WT" & dat$ReadCount[1]==0 ) {
	write(paste("Warning: No data in indel length input file:", infile), stderr())
	##dat[1,] <- c(sample, 0, 0, "WT", rep(0,5)) 
	#dat$IndelLength <- as.numeric(dat$IndelLength)
	#dat$ReadCount <- as.numeric(dat$ReadCount)
	NO_DATA = TRUE
}

firstElement <- function(vec) vec[1]

dat$Pos<-sapply(strsplit(dat$IndelStr, ":"), firstElement)
ag <- aggregate(dat$ReadCount, by=list(dat$Pos, dat$IndelLength), FUN=sum)
colnames(ag)<- c('pos', 'len', 'freq')
# pos is chr, len and freq are int

minRows = 21 

## R has trouble maintaining fixed bar width: bars are much wider when there are 
## a couple of rows than when there are a dozen rows. Hard-coded hacking to obtain
## fixed bar width is not portable between versions of ggplot. So to keep bar width 
## relatively slim for sample with only a few alleles, add some dummy rows. 

## min rows of high frequencies data
minRows = 19 

if ( nrow(ag) < minRows ) {
	vec=c(0)
	for (x in 1:floor(minRows/2)) { vec <- c(vec, x, -x) }
	
	present_lens = unique(ag$len)
	for (x in vec) {
		if ( x %in% present_lens == FALSE ) {
			ag[nrow(ag)+1, ] <- c("any", x, 0)	
			# When "any" is replaced by space, x-axis sorting is problematic.

			if (nrow(ag)==minRows) {
				## The above would cause all columns to be character
				ag$len <- as.numeric(ag$len)
				ag$freq <- as.numeric(ag$freq)
				break 
			}
		}
	}
}

## select max topN rows of high frequencies
topN = 21
n = ifelse(nrow(ag) > topN, topN, nrow(ag))
ag <- ag[with(ag, order(freq, decreasing=TRUE)), ][(1:n),] 

## create allele with pads so they are the same length for neat display
ag$len2 <- ifelse(ag$len>0, paste0('+', as.character(ag$len)), as.character(ag$len))  
fmt1 <- paste0("%", max(nchar(ag$pos)), "s")
fmt2 <- paste0("%", max(nchar(ag$len2)), "s")
ag$allele <- paste0(sprintf(fmt1, ag$pos), ":", sprintf(fmt2, ag$len2))

## indel type
ag$type <- ifelse(ag$len==0, "WT", 
	ifelse(ag$len>0, "Insertion", "Deletion"))

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

p<-ggplot(ag, aes(x=factor(allele), y=freq, fill=factor(type, levels=c("Deletion", "Insertion", "WT")))) +
	geom_bar(stat="identity", position="dodge", width=0.2) + 
	scale_fill_manual(values=c("WT"="#e74c3c", "Deletion"="#229954", "Insertion"="#2e86c1")) +
	labs(x="Allele Position and Indel Length", y="Reads", 
		title=paste("Allele Frequencies\nSample:", sample)) +
	theme(legend.title=element_blank(), legend.text=element_text(size=11, face="bold"), 
		legend.position='bottom',legend.direction='horizontal' ) +
	customize_title_axis(angle=90, size=13) +
	theme(axis.text.x=element_text(angle=90, family="Courier", face="bold", size=11))

if ( NO_DATA==TRUE ) {
	p <- p + scale_y_continuous(limits=c(0,500)) +
		annotate(geom='text', x=10, y=250, label="No reads at CRISPR site",
			family='Times', fontface="bold", size=5)
}

print(p)
