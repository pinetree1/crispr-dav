## Survey the amplicon: coverage, insertion, deletion  
## Locate sgRNA coordinates if available.
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
      --inf=pysamstat variation file, e.g. xx.var. Required.
      --sample=sample name. No space. Required.
      --ampStart=start of amplicon. Required.
      --ampEnd=end of amplicon. Required. 
      --hname=name of highlight region, e.g. sgRNA. 
      --hstart=highlight region start position, e.g. sgRNA start position. Optional.
      --hend=highlight region end position, e.g. sgRNA end position. Optional.
      --type=type of data: coverage, insertion, deletion. Optional. All types will be plotted by default. 
      --chr=chromosome name, e.g. 'hg19 chr3'. Optional.
      --outf=ouput image file prefix. Required. Extension, e.g. .cov.png/tif will be added. 
      --high_res=1 or 0. 1-create high resolution .tif image. 0-create png file.
      --help 	Print this message
	"))
}

## Parse arguments (we expect the form --arg=value)
parseArgs <- function(x) strsplit(sub("^--", "", x), "=")
argsDF <- as.data.frame(do.call("rbind", parseArgs(args)))
argsL <- as.list(as.character(argsDF$V2))
names(argsL) <- argsDF$V1

if ( is.null(argsL$inf) | is.null(argsL$outf) |is.null(argsL$ampStart) 
	| is.null(argsL$ampEnd) |is.null(argsL$sample) ) { 
	exit("Missing required argument")
}

## set the output file name and path
infile  <-argsL$inf
prefix <- argsL$outf
if (file.exists(infile)==FALSE) exit(paste("Could not find", infile))
ampStart <- as.numeric(argsL$ampStart)
ampEnd <- as.numeric(argsL$ampEnd)

hstart <- NULL
hend <- NULL
hname <- "CRISPR Guide" 
if (!is.null(argsL$hstart)) hstart <- as.numeric(argsL$hstart)
if (!is.null(argsL$hend)) hend <- as.numeric(argsL$hend)
if (!is.null(argsL$hname)) hname <- as.character(argsL$hname)
if (!is.null(argsL$hstart)) {
	if ( is.null(argsL$hend) ) {
		exit("Missing --hend")
	}
}

high_res = ifelse( is.null(argsL$high_res), 0, as.numeric(argsL$high_res))
plot_ext = ifelse( high_res==1, ".tif", ".png")

## read data
dat <- read.table(infile, header=TRUE, sep="\t")
if ( nrow(dat) == 0 ) {
	write(paste("Warning: No reads in amplicon:", infile), stderr())
} else {
	dat$PctInsertion <- dat$insertions/dat$reads_all * 100	
	dat$PctDeletion <- dat$deletions/dat$reads_all * 100
}

getMainTitle <- function(main_title, sub_title) {
	mt=ifelse(is.null(sub_title), main_title, paste0(main_title, "\n", sub_title))
}

create_plot <- function (ymax, ycol, xtitle, ytitle, mtitle, outfile) {
	if  ( nrow(dat) > 0 ) {
		p <- ggplot(dat, aes(x=pos, y=dat[,ycol]), environment = environment() ) + theme_bw() +
			geom_line(color="blue") +
			scale_x_continuous(breaks=ceiling(seq(ampStart, ampEnd, length.out=15))) 
	} else {
		p <- ggplot(dat, aes(x=pos, y=reads_all)) + theme_bw() + 
			scale_x_continuous(limits=c(ampStart, ampEnd)) +
			annotate(geom='text', x=(ampStart+ampEnd)/2, y=ymax/2, 
				label='No reads in amplicon', family='Times', fontface="bold", size=5)

	}

	p <- p + scale_y_continuous(limits=c(0, ymax)) +
		labs(x=xtitle, y=ytitle, title=mtitle) + customize_title_axis(angle=90)

	if ( !is.null(hstart) & !is.null(hend) & nrow(dat)> 0 ) {
		p<- p + geom_rect(aes(xmin=hstart, xmax=hend, ymin=-Inf, ymax=Inf, 
			fill=hname), alpha=0.01) +
			scale_fill_manual(limits=c(hname), values=c('grey')) + 
			theme(legend.title=element_blank(), 
				legend.key=element_rect(fill='grey'),
				legend.text=element_text(face="bold", size=11),
				legend.position="bottom",
				legend.direction="horizontal"
			)	
	}

	if ( high_res ) {
		tiff(filename=outfile, width=5, height=4, units='in', res=1200)	
	} else {
		png(filename=outfile, width=500, height=400)
	}
	on.exit(dev.off())
	print(p)
}

xtitle <- ifelse(is.null(argsL$chr), "Position", paste(argsL$chr, "Position"))
type <- ifelse(is.null(argsL$type), "all", argsL$type)
sub_title<- argsL$sample 

if ( type %in% c("all", "coverage") ) {
	mtitle <- getMainTitle("Depth of Coverage", sub_title)
	ytitle <- "Read Depths"
	ycol <- "reads_all"   # y column name
	outfile <- paste0(prefix, '.cov', plot_ext) 
	ymax = ifelse (nrow(dat)> 0, max(dat[,ycol]), 10000);
	create_plot (ymax, ycol, xtitle, ytitle, mtitle, outfile) 
}

#ymax=25
#if ( nrow(dat) > 0 ) {
#	ymax_ins = ceiling(max(dat$insertions/dat$reads_all * 100)) 
#	ymax_del = ceiling(max(dat$deletions/dat$reads_all * 100)) 
#	ymax = ifelse (ymax_ins > ymax, ymax_ins, ymax) 
#	ymax = ifelse (ymax_del > ymax, ymax_del, ymax) 	
#	for ( i in c(75, 50, 25) ) {
#		if (ymax > i) {
#			ymax = ifelse(i+25>100, 100, i+25)
#		}
#	}
#}

ymax = 10;   # min scale for indel plots 

if (type %in% c('all', 'insertion')){
	mtitle <- getMainTitle("Insertion Distribution", sub_title)
	ytitle <- "Insertion Read %"
	ycol <- "PctInsertion"
	outfile <- paste0(prefix, '.ins', plot_ext)
	if ( nrow(dat) > 0 ) {
		ymax_ins = ceiling(max(dat$insertions/dat$reads_all * 100))
		ymax = ifelse(ymax_ins > ymax, ymax_ins, ymax)
	}
	create_plot (ymax, ycol, xtitle, ytitle, mtitle, outfile) 
} 

if ( type %in% c('all', 'deletion') ) {
	mtitle <- getMainTitle("Deletion Distribution", sub_title)
	ytitle <- "Deletion Read %"
	ycol <- "PctDeletion"
	outfile <- paste0(prefix, '.del', plot_ext)
	if ( nrow(dat) > 0 ) {	
		ymax_del = ceiling(max(dat$deletions/dat$reads_all * 100))
		ymax = ifelse(ymax_del > ymax, ymax_del, ymax)
	}
	create_plot (ymax, ycol, xtitle, ytitle, mtitle, outfile) 
} 

