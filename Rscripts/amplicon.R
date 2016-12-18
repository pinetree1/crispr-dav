## Survey the amplicon: coverage, insertion, deletion  
## Locate sgRNA coordinates if available.
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
      --inf=pysamstat variation file, e.g. xx.var. Required.
      --sub=subtitle. Use quote if there are spaces.Optional.
      --hname=name of highlight region, e.g. sgRNA. Optional but required if --hstart is provided.
      --hstart=highlight region start position, e.g. sgRNA start position. Optional.
      --hend=highlight region end position, e.g. sgRNA end position. Optional.
      --type=type of data: coverage, insertion, deletion. Optional. All types will be plotted by default. 
      --chr=chromosome name, e.g. 'hg19 chr3'. Optional.
      --outf=ouput png file prefix. Required. Extension(.cov.png, .ins.png, .del.png) will be added. 
      --help 	Print this message
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
infile  <-argsL$inf
prefix <- argsL$outf
if (file.exists(infile)==FALSE) exit(paste("Could not find", infile))

hstart <- NULL
hend <- NULL
hname <- NULL
if (!is.null(argsL$hstart)) hstart <- as.numeric(argsL$hstart)
if (!is.null(argsL$hend)) hend <- as.numeric(argsL$hend)
if (!is.null(argsL$hname)) hname <- as.character(argsL$hname)
if (!is.null(argsL$hstart)) {
	if ( is.null(argsL$hend) | is.null(argsL$hname) ) {
		exit("Missing --hend or --hname")
	}
}

## read data
dat <- read.table(infile, header=TRUE, sep="\t")
if ( nrow(dat)== 0 ) { 
	exit("No data in input file")
}

mindepth<-1000  # min depth marking the start and end of amplicon region
h=1
t=nrow(dat)

h <- which(dat$reads_all>mindepth)[1]
if (is.na(h)) exit(paste("No position has depth >=", mindepth))
t <- tail(which(dat$reads_all>mindepth), n=1)
if ( t > nrow(dat) ) {
	exit("There is not enough data for plotting")
}

dat2 <- dat[h:t, ]

getMainTitle <- function(main_title, sub_title) {
	mt=ifelse(is.null(sub_title), main_title, paste0(main_title, "\n", sub_title))
}

create_plot <- function (dat, ycol, xtitle, ytitle, mtitle, outfile,
	hstart, hend, hname ) {

	## create the plot
	wt <- 500
	ht <- 600

	p<- ggplot(dat, aes(x=pos, y=dat[,ycol]), environment = environment() ) + 
		geom_line(color="blue") + 
		theme_bw() +
		scale_x_continuous(breaks=seq(min(dat$pos), max(dat$pos),by=50)) +
		labs(x=xtitle, y=ytitle, title=mtitle) + customize_title_axis(angle=90)

	if ( !is.null(hstart) & !is.null(hend) ) {
		p<- p + geom_rect(aes(xmin=hstart, xmax=hend, ymin=-Inf, ymax=Inf, 
			fill=hname), alpha=0.01) +
			scale_fill_manual(limits=c(hname), values=c('grey')) + 
			theme(legend.title=element_blank(), 
				legend.key=element_rect(fill='grey'),
				legend.text=element_text(face="bold", size=12),
				legend.position="bottom",
				legend.direction="horizontal"
			)	
	}

	png(filename=outfile, width=wt, height=ht)
	on.exit(dev.off())
	print(p)
}

xtitle <- ifelse(is.null(argsL$chr), "Position", paste(argsL$chr, "Position"))
type <- ifelse(is.null(argsL$type), "all", argsL$type)
sub_title<- ifelse(is.null(argsL$sub), NULL, argsL$sub)

if ( type %in% c("all", "coverage") ) {
	mtitle <- getMainTitle("Depth of Coverage", sub_title)
	ytitle <- "Read Depths"
	ycol <- "reads_all"   # y column name
	outfile <- paste0(prefix, '.cov.png') 
	create_plot (dat2, ycol, xtitle, ytitle, mtitle, outfile, hstart, hend, hname) 
}

if (type %in% c('all', 'insertion')){
	mtitle <- getMainTitle("Insertion Distribution", sub_title)
	ytitle <- "Insertion Read %"
	ycol <- "PctInsertion"
	dat2[[ycol]] <- dat2$insertions/dat2$reads_all * 100
	outfile <- paste0(prefix, '.ins.png')
	create_plot (dat2, ycol, xtitle, ytitle, mtitle, outfile, hstart, hend, hname)
} 

if ( type %in% c('all', 'deletion') ) {
	mtitle <- getMainTitle("Deletion Distribution", sub_title)
	ytitle <- "Deletion Read %"
	ycol <- "PctDeletion"
	dat2[[ycol]] <- dat2$deletions/dat2$reads_all * 100
	outfile <- paste0(prefix, '.del.png')
	create_plot (dat2, ycol, xtitle, ytitle, mtitle, outfile, hstart, hend, hname)
} 

