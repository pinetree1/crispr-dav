# Given a vector x, and a value y, find the indexes 
# of the first and last vector element >= y, and return the sequence  
# Author: X. Wang
ge_range <- function (x, y) {
	idx1 = which(x>=y)[1]
	idx2 = tail(which(x>=y), n=1)
	idx1:idx2
} 

## return the non-dot part of a file name
## If filename is test.tar.gz, this returns test
rm_all_ext <- function(filename) {
	fr <-basename(filename)
	if ( grepl("\\.", fr)) {
		fr <- sub("\\..*$", "", fr)
	}
	fr
}

## remove the last extension
## test.tar.gz would return test.tar
rm_last_ext <- function(filename) {
	fr <-basename(filename)
	if ( grepl("\\.", fr)) {
		fr <- sub("\\.[^.]*$", "", fr)
	}
	fr
}

## get command line script name
get_scriptname <- function() {
	args <- commandArgs(trailingOnly=FALSE)
	script.name <- sub("--file=", "", args[grep("--file=",args)])
}

## back and bold theme with any-angle tick text on x-axis
customize_title_axis <- function(angle=0, color="black", face="bold", family="Times", size=12) {
	c<-color
	f<-face
	fm<-family
	theme(axis.text.x=element_text(angle=angle, color=c, 
			family=fm, face="bold", size=size, vjust=0.5, hjust=0.5), 
		axis.text.y=element_text(color=c, family=fm, face=f, size=size),
		axis.title.x=element_text(color=c, family=fm, face=f, size=size, vjust=-0.2),
		axis.title.y=element_text(color=c, family=fm, face=f, size=size, vjust=1),
		plot.title=element_text(color=c, family=fm, face=f, size=size, hjust=0.5)
		)
}

exit <- function(msg="", status=1) {
	cat(msg, "\n")
	quit("no", status=status)
}

## this probably won't work in newer version of ggplot2,
## because the grobs[[4]] is not the same.

fixedWidth <- function(graph, width=0.1) {
	# Returns a new plottable object
	# Based on http://stackoverflow.com/questions/18429244/constant-width-in-ggplot-barplots
	# Created by Ron Ammar
	g2 <- graph

	#store the old widths
	old.unit <- g2$grobs[[4]]$children[[2]]$width[[1]]
	original.attibutes <- attributes(g2$grobs[[4]]$children[[2]]$width)

	#change the widths
	g2$grobs[[4]]$children[[2]]$width <- rep(width,
			length(g2$grobs[[4]]$children[[2]]$width))

	#copy the attributes (units)
	attributes(g2$grobs[[4]]$children[[2]]$width) <- original.attibutes

	#position adjustment (why are the bars justified left???)
	d <- (old.unit-g2$grobs[[4]]$children[[2]]$width[[1]])/2
	attributes(d) <- attributes(g2$grobs[[4]]$children[[2]]$x)
	g2$grobs[[4]]$children[[2]]$x <- g2$grobs[[4]]$children[[2]]$x+d

	return(g2)
}
