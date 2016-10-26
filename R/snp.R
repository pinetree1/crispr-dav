suppressMessages(library(ggplot2))
suppressMessages(library(reshape2))
options(scipen=999)

args<- commandArgs(trailingOnly=FALSE)
script.name<- sub("--file=", "", args[grep("--file=", args)])

args <- commandArgs(trailingOnly=TRUE)
if(length(args) < 1) {
	args<- c("--help")
}

if ( "--help" %in% args ) {
	stop(cat(script.name, "
	Arguments:
	--inf=pysamstats variation file. Required.
	--sample=sample name. No space. Required. 
	--chr=chromosome, e.g. 'hg19 chr3'. Optional.
	--hstart=highlight region start position, e.g. sgRNA start position. Required.
	--hend=highlight region end position, e.g. sgRNA end position. Required.
	--hname=name of highlight region, e.g. sgRNA. Required 
	--wing=number of bases on each site of sgRNA to see snp. Default: 50
	--outf=output png file. Required.
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
	| is.null(argsL$hname)
	| is.null(argsL$outf) 
	| is.null(argsL$outtsv)
){
	exit("Missing required argument")
}

infile <- argsL$inf
sample <- argsL$sample
hstart <- as.numeric(argsL$hstart)
hend <- as.numeric(argsL$hend)
outfile <- argsL$outf
outtsv <- argsL$outtsv
chr <- argsL$chr
wingLength <- 50
if (!is.null(argsL$wing)) {
    wingLength <- strtoi(argsL$wing)
}

#cat(infile, "hstart:", hstart, "hend:", hend, "chr:", chr)
if (file.exists(infile)==FALSE) exit(paste("Can not find", infile))

dat <- read.table(infile, sep="\t", header=TRUE, stringsAsFactors=FALSE)

h2 = hstart - wingLength - dat$pos[1];
h = ifelse(h2>1, h2, 1) 
t = h + 2* wingLength + hend - hstart;
if ( t-wingLength > nrow(dat) ) {
    exit("There is not enough data for plotting")
}
dat <- dat[h:t, ]
if (nrow(dat) == 0) {
	exit("No data in CRISPR site")
}

bases=c('A', 'C', 'G', 'T')
pctBases=paste0("Pct", bases)
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

n <- nchar(hend+wingLength)
format <- paste0("%0", n, "d")
dat$PosBase <- paste(sprintf(format, dat$pos), dat$ref, sep=" ")

# titles
xtitle <- paste(chr, "Position")
ytitle <- "% Reads"
mtitle <- paste("SNP Distribution\n", sample)

## set Pct of a base to be 0 when the base depth is the same as matches
for ( i in c(1:4) ) {
	idx= dat$matches==dat[[bases[i]]]
	dat[idx,][[pctBases[i]]]=0	
} 
datm <- melt(dat, id.vars="PosBase", measure.vars=pctBases)

# If any base has mismatch rate >=0.5%, it will be labelled.

p<-ggplot(datm, aes(x=PosBase, y=value, fill=variable)) +
	ylim(0, ymax) +
	geom_bar(stat='identity') +
	geom_text(aes(label=ifelse(value>=0.5, round(value,1), ''), vjust=0)) +
	theme_bw() + 
	theme(axis.text.x=element_text(angle=90, family="Courier", face="bold", vjust=0.5),
		axis.text.y=element_text(face="bold"),
		axis.title.x=element_text(face="bold", vjust=-0.2),
		axis.title.y=element_text(face="bold", vjust=1),
		plot.title=element_text(face="bold")
		) +
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
  annotate(geom='text', x=hmid_x, y=guide_y*1.1, label='sgRNA Guide', 
	family='Times', fontface="bold")


wt <- 12*nrow(dat)
ht <- 500
png(filename=outfile, width=wt, height=ht)
p
invisible(dev.off())

