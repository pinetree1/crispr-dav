This example uses an amplicon sequence as reference.

Steps to test the pipeline:
1. Modify the paths of applications in conf.txt according to your environment.
2. Start the pipeline: 

	sh run.sh &> r.log &

This would start the pipeline if there is no error. If there is error
importing python modules, find their path and include it in the run.sh by
editing the export statement in the script. 

Intermediate files will be in 'align' directory. Results will be 
in 'deliverables' directory.
