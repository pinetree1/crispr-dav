# Must be root
if [ "$USER" != "root" ]; then
	echo "You must be root to do the installations."
	exit
fi

#install cpanm if needed:
which cpanm
if [ $? -ne 0 ]
	curl -L https://cpanmin.us | perl - --sudo App::cpanminus
fi

#install required modules:
cpanm Config::Tiny
cpanm CJFIELDS/BioPerl-1.6.924.tar.gz
cpanm Excel::Writer::XLSX
cpanm Spreadsheet::ParseExcel
cpanm Spreadsheet::XLSX
cpanm Time::HiRes
cpanm JSON
cpanm CGI
cpanm URI::Escape
