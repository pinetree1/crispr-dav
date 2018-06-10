The example1_a is similar to example1, but uses a samplesheet. This is more 
convenient to run the pipeline, especially when there are multiple guides
and samples. 

Steps to run pipeline:

   (1) Edit the ../../conf.txt 

        Change the paths of genomex files and software to suit your installations. 

   (2) ../../prepare_run.pl samplesheet.txt 

        This will generate a directory (name starting with 'amp') for each amplicon. By 
        default, the script uses conf.txt in crispr-dav root directory, and the fastq 
        path specified in the samplesheet. You can provide conf.txt and fastq path 
        via command line options as well. The script will find the locations of the 
        guide sequences via alignment to the genome specified in the samplesheet and 
        conf.txt. The script generates a temporary working directory named 'prep', 
        which will disappear upon successful processing, and remain if error occurs. 

   (3) cd to an amplicon directory 

   (4) sh run.sh
