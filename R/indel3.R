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

dat <- read.table(file=infile, sep="\t", header=TRUE)

cols <- c("WtReads", "IndelReads", "InframeIndel")
data <- melt(dat, id.vars="Sample", measure.vars=cols)
ytitle="Number of Reads"
maintitle="Read Counts at CRISPR Site"

create_plot <- function (data, imgfile, cols, ytitle, maintitle) {	
	n<- length(unique(data$Sample))
	h<-500
	w<- ifelse(n>10, w<-50*n, h)

	legends <- c("WT", "All Indel", "Inframe Indel")

	cat("called: file:", imgfile, ", yt:", ytitle, ", main:", maintitle, "\n")
	cat("cols:", cols, "\n")
	cat(str(data), "\n")

	png(filename=imgfile, height=h, width=w)
	ggplot(data, aes(x=Sample, y=value, fill=variable)) + 
		geom_bar(stat='identity', position=position_dodge(), width=0.35) +
		labs(y=ytitle, title=maintitle) + 
		scale_fill_discrete(name="Read Type", breaks=cols, labels=legends) +
		customize_title_axis(angle=45) +
		theme(legend.text=element_text(size=13),
			legend.title=element_text(size=13)
			) +
		geom_text(aes(label=value, ymax=value), position=position_dodge(width=0.9), 
			check_overlap=TRUE, vjust=-0.5, size=4)

	invisible(dev.off())
}

#cols <- c("WtReads", "IndelReads", "InframeIndel")
#data <- melt(dat, id.vars="Sample", measure.vars=cols)
#ytitle<-"Number of Reads"
#maintitle<-"Read Counts at CRISPR Site"
create_plot(data, cnt_outfile, cols, ytitle, maintitle) 
