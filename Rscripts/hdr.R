## Create a plot of HDR frequencies 
## Author: X. Wang
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
      --inf=HDR stat file, e.g. TGFBR1_CR1_hdr_stat.txt. Required.
      --sub=subtitle. Optional.
      --high_res=1 or 0. 1-create high resolution .tif image. 0-create png file.
      --outf=ouput image file. Required.
      --help    Print this message
    "))
}

suppressMessages(library(ggplot2))
suppressMessages(library(reshape2))
options(scipen=999)
Sys.setlocale("LC_ALL", "en_US.UTF-8")

## Parse arguments (we expect the form --arg=value)
parseArgs <- function(x) strsplit(sub("^--", "", x), "=")
argsDF <- as.data.frame(do.call("rbind", parseArgs(args)))
argsL <- as.list(as.character(argsDF$V2))
names(argsL) <- argsDF$V1
if ( is.null(argsL$inf) | is.null(argsL$outf) ) {
    exit("Missing required argument")
}

## set the output file name and path
infile  <-argsL$inf
outfile <- argsL$outf
if (file.exists(infile)==FALSE) exit(paste("Could not find", infile))

mtitle <- 'HDR Oligo Frequencies'
if ( !is.null(argsL$sub) ) {
    mtitle <- paste0(mtitle, "\n", argsL$sub)
}

high_res = ifelse(is.null(argsL$high_res), 0, as.numeric(argsL$high_res))
 
## read data file 
dat <- read.table(file=infile, sep="\t", header=TRUE )
n<- nrow(dat)
if (n==0) write(paste("Warning: No data in HDR input file:", infile), stderr())

vnames <- c('PctNonOligo', 'PctPartialOligo', 'PctEditedOligo', 'PctPerfectOligo')
vlabels <- c('Non-Oligo  ', 'Partial  ', 'Edited  ', 'Perfect  ')
annot <- 'Total number of reads spanning HDR mutations' 

datm <- melt(dat, id.vars=c('Sample', 'TotalReads'), measure.vars=vnames)

limit_y=115
annot_y=111
if (high_res) {
	limit_y=120
	annot_y=115
}

p<- ggplot(datm, aes(x=Sample, y=value, fill=factor(variable, levels=vnames))) + 
	theme_bw() + 
	scale_y_continuous(breaks=c(0,25,50,75,100), limits=c(0,limit_y)) +
	scale_fill_manual(name="Oligo Type: ", breaks=vnames, labels=vlabels, 
		values=c('PctNonOligo'="#58D3F7", 'PctPartialOligo'="#f4d03f", 
			'PctEditedOligo'="#2E64FE", 'PctPerfectOligo'="#229954")) +
	labs(x='Sample', y='% Reads', title=mtitle) +
	customize_title_axis(angle=45)  

if ( n > 0 ) {
	p <- p + geom_bar(stat='identity', width=0.3) +
	theme(legend.position="bottom", legend.direction="horizontal",	
		legend.title = element_text(size=12, face="bold"),
		legend.text = element_text(size=12, face="bold")) + 
	geom_text(aes(label=ifelse(variable=="PctNonOligo", TotalReads, ' ')),
		size=4, vjust = -0.5, position = "stack") +
	geom_text(aes(label=ifelse(variable=="PctPerfectOligo" & value>0.1, value, ' ')),
		size=4, vjust=1, position='stack') +
	annotate(geom='text', x=1, y=annot_y, label=annot, size=5, 
		family='Times', fontface="plain", hjust=0, vjust=0) 
} else {
	p<- p + annotate(geom='text', x=1, y=50, label="No reads at CRISPR site",
		size=5, family='Times', fontface="bold" ) +
		theme(axis.text.x = element_blank())	
}


if ( high_res ) {
	h <- 4.5
	w <- ifelse(n<10, h*1.25, n*h*0.125)
	tiff(filename=outfile, width=w, height=h, units='in', res=1200)
} else {
	h<-400
	barspace=60
	w<- ifelse( n*barspace<h, h, n*barspace)
	png(filename=outfile, width=w, height=h)
}

print(p)
invisible(dev.off())
