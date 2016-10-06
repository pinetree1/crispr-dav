## Create a read count plot of indel
suppressMessages(library(ggplot2))
library(reshape2)

args <- commandArgs(trailingOnly=FALSE)
script.name <- sub("--file=", "", args[grep("--file=",args)])
script.path <- dirname(script.name)
source(file.path(script.path, "func.R"))

args <- commandArgs(trailingOnly=TRUE)

if (length(args) != 3) {
	cat(paste("Usage:", script.name, "{infile, e.g. <site>.pct}", "{output count plot file} {ouput pct plot file}\n"))
	q()
}

## set the output file name and path
infile<-args[1]
cnt_outfile <- args[2]
pct_outfile <- args[3]
if (file.exists(infile)==FALSE) exit(paste("Could not find", infile))
imgfile<-cnt_outfile
h<-500
w<-500
png(filename=imgfile, height=h, width=w)

invisible(dev.off())

#cols <- c("WtReads", "IndelReads", "InframeIndel")
#data <- melt(dat, id.vars="Sample", measure.vars=cols)
#ytitle<-"Number of Reads"
#maintitle<-"Read Counts at CRISPR Site"
#create_plot(data, cnt_outfile, cols, ytitle, maintitle) 
