## Create plots of indel read count and pct 
## Author: X. Wang
suppressMessages(library(ggplot2))
library(reshape2)
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
      --inf=indel pct file, e.g. <site>.pct. Required.
      --high_res=1 or 0. 1-create high resolution .tif image. 0-create png file.
      --cntf=ouput indel count image file. Required.
      --pctf=ouput indel percentage image file. Required.
      --help    Print this message
  "))
}

## Parse arguments (we expect the form --arg=value)
parseArgs <- function(x) strsplit(sub("^--", "", x), "=")
argsDF <- as.data.frame(do.call("rbind", parseArgs(args)))
argsL <- as.list(as.character(argsDF$V2))
names(argsL) <- argsDF$V1
if ( is.null(argsL$inf) | is.null(argsL$cntf) | is.null(argsL$pctf) ) {
    exit("Missing required argument")
}

## set the output file name and path
infile <- argsL$inf
cnt_outfile <- argsL$cntf
pct_outfile <- argsL$pctf

if (file.exists(infile)==FALSE) exit(paste("Could not find", infile))

high_res = ifelse(is.null(argsL$high_res), 0, as.numeric(argsL$high_res))

## function to create plot
create_plot <- function (data, imgfile, cols, ytitle, maintitle, high_res) {	
	n<- length(unique(data$Sample))
	legends <- c("WT", "All Indel", "Inframe Indel")

	p <-ggplot(data, aes(x=Sample, y=value, fill=variable)) + 
		geom_bar(stat='identity', position=position_dodge(), width=0.35) +
		labs(y=ytitle, title=maintitle) + 
		scale_fill_discrete(name="Read Type", breaks=cols, labels=legends) +
		customize_title_axis(angle=45) +
		theme(axis.text.x=element_text(vjust=1, hjust=1)) +
		theme(legend.text=element_text(size=13), legend.title=element_text(size=13)) +
		geom_text(aes(label=value, ymax=value), position=position_dodge(width=0.5), 
			check_overlap=TRUE, vjust=-0.5, size=3)

	if ( high_res ) {
		h<-4
		w<-ifelse(n>10, 0.5*n, h*1.25)
		tiff(filename=imgfile, width=w, height=h, units='in', res=1200)
	} else {
		h<-400
		w<- ifelse(n>10, 50*n, h*1.25)
		png(filename=imgfile, height=h, width=w)
	}

	on.exit(dev.off())
	print(p)
}

## read input
dat <- read.table(file=infile, sep="\t", header=TRUE)

## plot for read count
cols <- c("WtReads", "IndelReads", "InframeIndel")
data <- melt(dat, id.vars="Sample", measure.vars=cols)
ytitle<-"Number of Reads"
maintitle<-"Read Counts at CRISPR Site"
create_plot(data, cnt_outfile, cols, ytitle, maintitle, high_res) 

## plot for indel pct
cols <- c("PctWt", "PctIndel", "PctInframeIndel")
data <- melt(dat, id.vars="Sample", measure.vars=cols)
ytitle<-"Percentage of Reads"
maintitle<-"Percentages of reads at CRISPR Site"
create_plot(data, pct_outfile, cols, ytitle, maintitle, high_res) 
