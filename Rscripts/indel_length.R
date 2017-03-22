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
      --high_res=1 or 0. 1-create high resolution .tif image. 0-create png file.
      --outf=output image file. Required.
      --outf2=output image file with WT shown. Required.
      --help    Print this message
  "))
}

## Parse arguments (we expect the form --arg=value)
parseArgs <- function(x) strsplit(sub("^--", "", x), "=")
argsDF <- as.data.frame(do.call("rbind", parseArgs(args)))
argsL <- as.list(as.character(argsDF$V2))
names(argsL) <- argsDF$V1
if ( is.null(argsL$inf) | is.null(argsL$outf) | is.null(argsL$outf2) ) {
    exit("Missing required argument")
}

## set the output file name and path
infile<- argsL$inf
outfile <- argsL$outf 
outfile2 <- argsL$outf2 
high_res = ifelse(is.null(argsL$high_res), 0, as.numeric(argsL$high_res))

if (file.exists(infile)==FALSE) exit(paste("Could not find", infile))
## create the plot
dat <- read.table(file=infile, sep="\t", header=TRUE )

dat1 <- dat[dat$IndelLength !=0, ]   # remove the WT
if (nrow(dat1)==0) exit(paste("No data in input file", infile), 0)

xlabel = "Indel Length (<0:Deletion, >0:Insertion)"
xlabel2 = "Indel Length (<0:Deletion, 0:WT, >0:Insertion)"

create_plot <- function(data, xlab, imgfile) {
	samplename <- data$Sample[1]  

	ag <- aggregate(data$ReadCount, by=list(data$IndelLength), FUN=sum)
	colnames(ag)<- c('bin', 'freq')
	rows <- nrow(ag)

	if (rows == 1 ) {
		if ( ag[1,2]==0 ) {
			exit("No reads", 0)
		}
	} 

	## select max topN rows of high frequencies
	topN = 20
	n = ifelse(rows >=topN, topN, rows)	
	ag <- ag[with(ag, order(freq, decreasing=TRUE)), ][(1:n),]	

	# number of indel lengths
	if ( high_res ) {
        h<-4
        w<-ifelse(n>40, 0.13*n, h*1.25)
        tiff(filename=imgfile, width=w, height=h, units='in', res=1200)
	} else {
		h<-400
		w<- ifelse(n>40, 13*n, h*1.25)
		png(filename=imgfile, height=h, width=w)
	}

	on.exit(dev.off())

	p<-ggplot(ag, aes(x=factor(bin), y=freq)) +
		geom_bar(stat="identity", position="dodge", width=0.2) + 
		labs(x=xlab, y="Reads", title=paste("Sample:", samplename)) +
		customize_title_axis(angle=90) 

	print(p)
	#g<- ggplotGrob(p)
	#plot(fixedWidth(g, width=0.01))
}

create_plot(dat1, xlabel, outfile)
create_plot(dat, xlabel2, outfile2)
