## Create a plot of point mutations around crispr site
## Author: X. Wang
suppressMessages(library(ggplot2))
suppressMessages(library(reshape2))
options(scipen=999)
Sys.setlocale("LC_ALL", "en_US.UTF-8")

args<- commandArgs(trailingOnly=FALSE)
script.name<- sub("--file=", "", args[grep("--file=", args)])
script.path <- dirname(script.name)
source(file.path(script.path, "func.R"))

args <- commandArgs(trailingOnly=TRUE)
if(length(args) < 1) {
	args<- c("--help")
}

if ( "--help" %in% args ) {
	stop(cat(script.name, "Create SNP plot", "
	Arguments:
	--inf=pysamstats variation file. Required.
	--sample=sample name. No space. Required. 
	--chr=chromosome, e.g. 'hg19 chr3'. Optional.
	--sameRead=1 or 0. Optional. Default: 0 (all positions not necessarily on same read)
	--hstart=highlight region start position, e.g. sgRNA start position. Required.
	--hend=highlight region end position, e.g. sgRNA end position. Required.
	--rangeStart=start of SNP plot range. Required. 
	--rangeEnd=end of SNP plot range. Required. 
	--high_res=1 or 0. 1-create high resolution .tif image. 0-create png file.
	--outf=output plot file. Required.
	--outtsv=output tsv file. Required.
	--help Print this message
	"))
}

## parse arguments
parseArgs <- function(x) strsplit(sub("^--", "", x), "=")
argsDF <- as.data.frame(do.call("rbind", parseArgs(args)))
argsL <- as.list(as.character(argsDF$V2))
names(argsL) <- argsDF$V1
if (is.null(argsL$inf) 
	| is.null(argsL$sample)
	| is.null(argsL$hstart)
	| is.null(argsL$hend)
	| is.null(argsL$rangeStart)
	| is.null(argsL$rangeEnd)
	| is.null(argsL$outf) 
	| is.null(argsL$outtsv)
){
	exit("Missing required argument")
}

infile <- argsL$inf
sample <- argsL$sample
hstart <- as.numeric(argsL$hstart)
hend <- as.numeric(argsL$hend)
rangeStart <- as.numeric(argsL$rangeStart)
rangeEnd <- as.numeric(argsL$rangeEnd)
outfile <- argsL$outf
outtsv <- argsL$outtsv
chr <- argsL$chr

if (file.exists(infile)==FALSE) exit(paste("Can not find", infile))
high_res = ifelse(is.null(argsL$high_res), 0, as.numeric(argsL$high_res))
dat <- read.table(infile, sep="\t", header=TRUE, stringsAsFactors=FALSE)

blank_plot <- function(dat, xtitle, ytitle, mtitle, outfile) {
	p <- ggplot(dat, aes(x=pos, y=reads_all)) + theme_bw() +
		scale_x_continuous(limits=c(rangeStart, rangeEnd)) +
		labs(x=xtitle, y=ytitle, title=mtitle) +
		customize_title_axis(angle=90) +
		annotate(geom='text', x=(rangeStart+rangeEnd)/2, y=10, size=5,
			label='No reads in and round CRISPR site', family='Times', fontface="bold") +
		theme(axis.text.y = element_blank())

	if ( high_res ) {
    	tiff(filename=outfile, width=5, height=4, units='in', res=1200)
	} else {
    	png(filename=outfile, width=500, height=400)
	}
	print(p)
	invisible(dev.off())
}

# titles
pos_info = ifelse(is.null(argsL$sameRead), "(Not neccessarily on same read)", "(All on same read)") 
xtitle <- paste(chr, "Position", pos_info)
ytitle <- "% Reads"
mtitle <- paste("SNP Distribution\n", sample)

if (nrow(dat)==0) { 
	blank_plot(dat, xtitle, ytitle, mtitle, outfile)
	exit(paste("Warning: No dat in input file", infile), 0)
} 

# data in the range
dat <- dat[dat$pos >= rangeStart & dat$pos <= rangeEnd, ]

## fields for outtsv file
bases=c('A', 'C', 'G', 'T')
pctBases=paste0("Pct", bases)
fs <- c('Sample', 'chrom', 'pos', 'ref', 'total', bases, pctBases)

if (nrow(dat)==0) {
	blank_plot(dat, xtitle, ytitle, mtitle, outfile)
    fileConn <- file(outtsv)
    writeLines(paste(fs, collapse="\t"), fileConn)
    close(fileConn)
	exit("Warning: No data in and around CRISPR site", 0)
}

dat$total = dat$A +  dat$T + dat$C + dat$G
dat$Sample = sample
for ( i in c(1:4) ) {
	dat[[pctBases[i]]] <- round(dat[[bases[i]]] * 100/dat$total, 2)
}


fs <- c('Sample', 'chrom', 'pos', 'ref', 'total', bases, pctBases)
write.table(dat[,fs], file=outtsv, sep="\t", row.names=FALSE, col.names=TRUE, quote=FALSE)

maxPctSnp <- max(100*(1-dat$matches/dat$total)) + 5
ymin = 5 
ymax= ifelse(maxPctSnp>ymin, maxPctSnp, ymin)

n <- nchar(rangeEnd)
format <- paste0("%0", n, "d")
dat$PosBase <- paste(sprintf(format, dat$pos), dat$ref, sep=" ")

## set Pct of a base to be 0 when the base depth is the same as matches
for ( i in c(1:4) ) {
	idx= dat$matches==dat[[bases[i]]]
	dat[idx,][[pctBases[i]]]=0	
} 
datm <- melt(dat, id.vars="PosBase", measure.vars=pctBases)

# min mismatch rate(%) to label the SNP rate in plot.
min_snp = 1;

p<-ggplot(datm, aes(x=PosBase, y=value, fill=variable)) +
	ylim(0, ymax) +
	geom_bar(stat='identity') +
	geom_text(aes(label=ifelse(value>=min_snp, round(value,1), ''), vjust=0)) +
	theme_bw() + 
	scale_fill_discrete(breaks=pctBases, labels=bases) +
	theme(axis.text.x=element_text(angle=90, family="Courier", face="bold", vjust=0.5, size=10),
		axis.text.y=element_text(face="bold", size=12),
		axis.title.x=element_text(face="bold", vjust=-0.2),
		axis.title.y=element_text(face="bold", vjust=1),
		plot.title=element_text(face="bold", hjust=0.5)) +
	labs (x=xtitle, y=ytitle, title=mtitle) +
	theme(legend.title=element_blank(), 
		legend.text=element_text(face="bold", size=12),
		legend.position='bottom', 
		legend.direction='horizontal') 

## sgRNA guide region
# sgRNA start at '114680479 T', end at: '114680498 G'. This can also be used in x value
# On x axis, x implicit value is 1, 2, 3 ...

# Find highlight line segment start and end
hstart_x = hstart - dat$pos[1] + 1
hend_x = hend - dat$pos[1] + 1

hmid_x = hstart_x + (hend_x - hstart_x + 1)/2

## Highlight line's y position
guide_y =  ymax/2
p<- p + geom_segment(aes(x=hstart_x, y=guide_y, xend=hend_x, yend=guide_y)) +
  annotate(geom='text', x=hmid_x, y=guide_y*1.2, label='sgRNA Guide Range', 
	family='Times', fontface="bold", size=5)


if ( high_res ) {
	ht <- 4
	wt <- 0.1*nrow(dat)
	if (wt < 5) { wt = 5 }
	tiff(filename=outfile, width=wt, height=ht, units='in', res=1200)
} else {
	wt <- 12*nrow(dat)
	if ( wt < 600 ) {
		wt <- 600
	}
	ht <- 400
	png(filename=outfile, width=wt, height=ht)
}

print(p)
invisible(dev.off())

