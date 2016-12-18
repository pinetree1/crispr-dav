## Create a plot of indel length vs count
suppressMessages(library(ggplot2))
options(scipen=999)

args <- commandArgs(trailingOnly=FALSE)
script.name <- sub("--file=", "", args[grep("--file=",args)])
script.path <- dirname(script.name)
source(file.path(script.path, "func.R"))

args <- commandArgs(trailingOnly=TRUE)

if (length(args) != 3) {
	exit(paste("Usage:", script.name, "{input indel detail file for single sample, e.g, <sample>.<site>.len}", 
		"{output image png filename}", "{output image png filename2 with WT shown}"))
}

## set the output file name and path
infile<-args[1]
outfile <- args[2]
outfile2 <- args[3]

if (file.exists(infile)==FALSE) exit(paste("Could not find", infile))
## create the plot
dat <- read.table(file=infile, sep="\t", header=TRUE )

dat1 <- dat[dat$IndelLength !=0, ]   # remove the WT
if ( nrow(dat1)==0 ) {
	exit("No data in input file")
}

xlabel = "Indel Length (<0:Deletion, >0:Insertion)"
xlabel2 = "Indel Length (<0:Deletion, 0:WT, >0:Insertion)"

create_plot <- function(data, xlab, pngfile) {
	samplename <- data$Sample[1]  

	ag <- aggregate(data$ReadCount, by=list(data$IndelLength), FUN=sum)
	colnames(ag)<- c('bin', 'freq')
	rows <- nrow(ag)

	if (rows == 1 ) {
		if ( ag[1,2]==0 ) {
			exit("No reads")
		}
	} 

	## select max topN rows of high frequencies
	topN = 20
	n = ifelse(rows >=topN, topN, rows)	
	ag <- ag[with(ag, order(freq, decreasing=TRUE)), ][(1:n),]	

	# number of indel lengths
	h<-500
	w<- ifelse(n>40, 13*n, h)

	png(filename=pngfile, height=h, width=w)
	on.exit(dev.off())

	p<-ggplot(ag, aes(x=factor(bin), y=freq)) +
		geom_bar(stat="identity", width=0.2) + 
		labs(x=xlab, y="Reads", title=paste("Sample:", samplename)) +
		customize_title_axis(angle=90) 

	print(p)
	#g<- ggplotGrob(p)
	#plot(fixedWidth(g, width=0.01))
}

create_plot(dat1, xlabel, outfile)
create_plot(dat, xlabel2, outfile2)
