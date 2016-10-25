# Must be root
if [ "$USER" != "root" ]; then
	echo "You must be root to do the installations."
	exit
fi

#install cpanm if needed:
which cpanm
if [ $? -ne 0 ]; then
	curl -L https://cpanmin.us | perl - --sudo App::cpanminus
fi

#install required perl modules:
cpanm Config::Tiny
cpanm Excel::Writer::XLSX
cpanm Spreadsheet::ParseExcel
cpanm Spreadsheet::XLSX
cpanm Time::HiRes
cpanm JSON
cpanm CGI
cpanm URI::Escape
cpanm CJFIELDS/BioPerl-1.6.924.tar.gz

# install pysam and pysamstats
pip install pysam==0.8.4
pip install pysamstats
 
