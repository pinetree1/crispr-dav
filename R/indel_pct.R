## Create a pct plot of indel
suppressMessages(library(ggplot2))
library(reshape2)

args <- commandArgs(trailingOnly=FALSE)
script.name <- sub("--file=", "", args[grep("--file=",args)])
script.path <- dirname(script.name)
source(file.path(script.path, "func.R"))

args <- commandArgs(trailingOnly=TRUE)

if (length(args) != 2) {
	cat(paste("Usage:", script.name, "{input indel summary file}", "{output image png file}\n"))
	q()
}

## set the output file name and path
infile<-args[1]
outfile <- args[2]
if (file.exists(infile)==FALSE) exit(paste("Could not find", infile))

## create the plot
dat <- read.table(file=infile, sep="\t", header=TRUE)
cols <- c("Pct.WT", "Pct.Indel", "Pct.Inframe.Indel");
legends <- c("WT", "All Indel", "Inframe Indel");
dat.m <- melt(dat, id.vars="Sample", measure.vars=cols)

# The value field cannot be completely NA.
if ( nrow(dat.m)==sum(is.na(dat.m$value)) ) {
	warning("All values in Pct.Indela and Pct.Inframe.Indel are NA. Cannot create plot.\n")
	q("no")
}

# number of samples
n <- nlevels(dat$Sample)
h<-500
w<-h
if ( n > 10 ) {
	w<-50*n
}

png(filename=outfile, height=h, width=w)

ggplot(dat.m, aes(x=Sample, y=value, fill=variable)) + 
geom_bar(stat='identity', position=position_dodge(), width=0.35) +
labs(x="Sample", y="Pct of Reads", title="Read Percentages at CRISPR Site") + 
scale_fill_discrete(name="Type", breaks=cols, labels=legends) +
customize_title_axis(angle=45)+
theme(legend.text=element_text(size=12)) +
geom_text(aes(label=value, ymax=value), position=position_dodge(width=0.9), 
	check_overlap=TRUE, vjust=-0.5, size=4)
# the ymax in geom_text prevents warning message: ymax not defined: adjusting position using y instead

invisible(dev.off())
