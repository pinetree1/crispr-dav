# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
package BMS::TableReader;
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

=head1 DESCRIPTION

=head1 SYNOPSIS

=head1 AUTHOR

Charles Tilford <podmail@biocode.fastmail.fm>

//Subject __must__ include 'Perl' to escape mail filters//

=head1 LICENSE

Copyright 2014 Charles Tilford

 http://mit-license.org/

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
  ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.

=cut

my $VERSION = 
    ' $Id$ ';

use strict;
use vars qw(@ISA);
use BMS::ErrorInterceptor;
#use Spreadsheet::ParseExcel;
#use lib '/stf/biocgi/tilfordc/patch_lib';
#use Spreadsheet::XLSX;

@ISA = qw(BMS::ErrorInterceptor);

our $GlobalHandleCounter = 0;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {
        HAS_HEADER  => 0,
        PUSH        => [],
        PUSH_LINE   => [],
        SCAN_REJECT => [],
        'FORMAT'    => '',
        EXCELDAT    => undef,
        FILEDAT     => undef,
    };
    bless ($self, $class);
    my $args = $self->parseparams
        ( -file  => "",
          @_ );
    $self->quotes( $args->{QUOTE} || $args->{QUOTES});
    $self->column_case_matters( $args->{COLCASE} );
    $self->column_whitespace_matters( $args->{COLWS} );
    if (my $cm = $args->{COLMAP}) {
        while (my ($in, $out) = each %{$cm}) {
            $self->remap_header_name( $in, $out );
        }
    }
    $self->intercept_errors();
    foreach my $safeToIgnore 
        ("ConfigLocal",
         'Argument "#NAME?" isn\'t numeric in int',
         "wrapped in pack",
         "Can't locate Encode/ConfigLocal.pm",
         "Can't locate Digest/MD4.pm",
         "Can't locate Digest/Perl/MD4.pm",
         "Malformed UTF-8 character") {
            $self->ignore_error( $safeToIgnore);
        }
    $self->has_header( $args->{HASHEADER} || $args->{HEADER} );
    $self->limit( $args->{LIMIT} );
    $self->format( $args->{TYPE} || $args->{FORMAT} );
    $self->scan_until( $args->{SCAN} );
    $self->toss_filter( $args->{TOSSFILTER} );
    $self->keep_filter( $args->{KEEPFILTER} );
    $self->input( $args->{INPUT} || $args->{FILE} );
    return $self;
}

sub DESTROY {
    my $self = shift;
    return unless ($self);
    if (my $tmp = $self->{TEMP_FILE}) {
        unlink($tmp);
    }
}

sub has_header {
    my $self = shift;
    if (defined $_[0]) {
        if (!$_[0]) {
            $self->{HAS_HEADER} = 0;
        } else {
            $self->{HAS_HEADER} = $_[0] =~ /^\d+$/ ? $_[0] : 1;
        }
    }
    return $self->{HAS_HEADER};
}

sub separator {
    my $self = shift;
    if (my $sep = shift) {
        $self->{SEPARATOR} = $sep;
    }
    return $self->{SEPARATOR};
}

sub quotes {
    my $self = shift;
    if (my $sep = shift) {
        $self->{QUOTES} = [$sep];
    }
    return $self->{QUOTES};
}

sub header {
    my $self = shift;
    my ($ws, $num) = $self->select_sheet();
    my @rv;
    if (defined $num) {
        @rv = @{$self->{HEADER}[$num] || []};
    }
    return wantarray ? @rv : \@rv;
}

sub set_header {
    my $self = shift;
    my ($ws, $num) = $self->select_sheet();
    my @rv = @{$self->{HEADER}[$num] = shift || []};
    return wantarray ? @rv : \@rv;
}

sub file_path {
    my $self = shift;
    return exists $self->{FILEDAT} ? $self->{FILEDAT}{path} : "";
}

sub column_name_to_index {
    my $self = shift;
    my @head = $self->header;
    my @nums;
    my %ok = map { uc($self->remap_header_name($_)) => 1 } @_;
    delete $ok{''};
    for my $h (0..$#head) {
        my $name = $head[$h];
        push @nums, $h if ($ok{ defined $name ? uc($name) : ''});
    }
    return wantarray ? @nums : $nums[0];
}

sub column_name_to_number {
    my $self = shift;
    my @rv   = map { $_ + 1 } $self->column_name_to_index( @_ );
    return wantarray ? @rv : $rv[0];
}

sub column_number_to_alphabet {
    my $self = shift;
    my $num  = shift;
    return "" if (!$num || $num !~ /^\d+$/);
    my @letters;
    while ($num > 0) {
        my $mod = ($num-1) % 26;
        unshift @letters, chr($mod + 65);
        $num -= ($mod + 1);
        $num /= 26;
    }
    return join('', @letters);
}

sub alphabet_to_column_number {
    my $self = shift;
    my $alpha = uc(shift || "");
    return "" unless ($alpha =~ /^[A-Z]+$/);
    my @letters = reverse split('', $alpha);
    my $val = 0;
    for my $l (0..$#letters) {
        $val += (26 ** $l) * (ord($letters[$l]) - 64);
    }
    return $val;
}

sub column_case_matters {
    # Set to true if you want 
    # "ThisCol" to remap to something different than "thiscol"
    my $self = shift;
    $self->{COL_CASE_MATTERS} = $_[0] if (defined $_[0]);
    return $self->{COL_CASE_MATTERS} || 0;
}

sub column_whitespace_matters {
    # Set to true if you want 
    # "This_Col" of "This-Col" to remap to something different than "This Col"
    my $self = shift;
    $self->{COL_WS_MATTERS} = $_[0] if (defined $_[0]);
    return $self->{COL_WS_MATTERS} || 0;
}

sub remap_header_name {
    my $self = shift;
    my ($nameReq, $newval) = @_;
    my $name = $self->_standard_column_for_matching( $nameReq );
    if (defined $newval) {
        if ($newval ne '') {
            $self->{COL_MAP}{$name} = $newval;
        } else {
            delete $self->{COL_MAP}{$name};
        }
        if (my $headers = $self->{HEADER}) {
            for my $snum (0..$#{$headers}) {
                my $head = $headers->[$snum];
                next unless ($head);
                for my $c (0..$#{$head}) {
                    my $col = $self->_standard_column_for_matching
                        ( $head->[$c] );
                    $head->[$c] = $newval if ($col eq $name);
                }
            }
        }
    }
    my $rv = $self->{COL_MAP}{$name};
    return defined $rv ? $rv : $nameReq;
}

sub remap_value {
    my $self = shift;
    my ($oldval, $newval) = @_;
    if (defined $newval) {
        $oldval = '--UNDEF--' unless (defined $oldval);
        $self->{VAL_MAP}{$oldval} = $newval;
    }
    
}

sub _standard_column_for_matching {
    my $self = shift;
    my $name = shift;
    $name = '' unless (defined $name);
    $name = uc($name) unless ($self->column_case_matters());
    $name =~ s/[_\-\s]+/ /g unless ($self->column_whitespace_matters());
    return $name;
}

sub ignore_unmapped_columns {
    my $self = shift;
    my @head = $self->header();
    if ($#head == -1) {
        $self->err
            ("Can not ignore unmapped columns before the header is known");
        return ();
    }
    my @ignored;
    my $colMap   = $self->{COL_MAP};
    my %isMapped = map { $_ => 1 } values %{$colMap};
    foreach my $name (@head) {
        push @ignored, $name unless ($isMapped{$name});
    }
    map { $self->ignore_column_name( $_ ) } @ignored;
    return @ignored;
}

sub ignore_column_name {
    my $self = shift;
    if (my $cn = shift) {
        if (my $unignore = shift) {
            delete $self->{IGNORE_COL}{$cn};
        } else {
            $self->{IGNORE_COL}{$cn} = 1;
        }
    }
}

sub progress {
    my $self = shift;
    my $st   = $self->{STARTED};
    my $rc   = $self->rowcount;
    return '' unless ($rc && $st);
    my $lt   = $self->{LASTPROG};
    my $nt   = time;
    my $tc   = $self->limit || $self->total_count;
    my $elapsed = $nt - $st;
    my $unit = 'sec';
    if ($elapsed > 100) { $elapsed /= 60; $unit = 'min' }
    my $msg = sprintf("%d row%s in %.1f %s", $rc, $rc == 1 ? '' : 's',
                      $elapsed, $unit);
    return $msg unless ($elapsed);
    my $rate = $rc / $elapsed;
    $msg .= sprintf(" (%.1f/%s)", $rate, $unit);
    return $msg unless ($tc && $rate);
    my $remain = ($tc - $rc) / $rate;
    $msg .= sprintf(" %3d%% %.1f %s remain", int(0.5 + 100 * $rc / $tc),
                    $remain, $unit);
}

sub limit {
    my $self = shift;
    if (defined $_[0] && $_[0] =~ /^\d+$/) {
        $self->{LIMIT} = $_[0];
    }
    return $self->{LIMIT};
}

sub extend_limit {
    my $self = shift;
    return unless $self->{LIMIT};
    my $num  = shift || 1;
    return $self->{LIMIT} += $num;
}

*row_count = \&rowcount;
sub rowcount {
    return shift->{ROWCOUNT};
}

sub total_count {
    my $self = shift;
    unless (defined $self->{TOTALCOUNT}) {
        my $it = $self->input_type || '';
        if ($it eq 'file') {
            $self->{TOTALCOUNT} = 0;
            my $fmt  = $self->format;
            my $file = $self->input;
            if ($file) {
                if ($fmt =~ /^(t|c)sv$/) {
                    my $num = `wc -l $file`;
                    if ($num =~ /(\d+)/) {
                        $num = $1 + 0;
                        $num -= $self->has_header;
                        $self->{TOTALCOUNT} = $num;
                    }
                }
            }
        }
    }
    return $self->{TOTALCOUNT};
}

sub scan_until {
    my $self = shift;
    $self->{SCAN_UNTIL} = &_standard_re($_[0]) if (defined $_[0]);
    return $self->{SCAN_UNTIL};
}

sub scan_rejects {
    return @{shift->{SCAN_REJECT}};
}

sub toss_filter {
    my $self = shift;
    if (defined $_[0]) {
        $self->{TOSS_FILTER} = $_[0];
    }
    return $self->{TOSS_FILTER};
}

sub keep_filter {
    my $self = shift;
    if (defined $_[0]) {
        $self->{TOSS_FILTER} = $_[0];
    }
    return $self->{TOSS_FILTER};
}

sub _standard_re {
    my ($re) = @_;
    return '' unless ($re);
    $re = "/$re/" unless ($re =~ /^\//);
    my $meth = 'sub { my ($val) = @_; return ($val =~ '.$re.') ? $1 || 1 : 0; }';
    return eval($meth);
}

sub _push {
    my $self = shift;
    # warn "PUSHING :".join("\n", map { join("+", @{$_}) } @_);
    push @{$self->{PUSH}}, @_;
}

sub _push_line {
    my $self = shift;
    # warn "PUSHING :".join("\n", map { join("+", @{$_}) } @_);
    push @{$self->{PUSH_LINE}}, @_;
}

sub _unshift {
    my $self = shift;
    # warn "PUSHING :".join("\n", map { join("+", @{$_}) } @_);
    unshift @{$self->{PUSH}}, @_;
}

sub format_from_file_name {
    my $self = shift;
    my ($file) = @_;
    return undef unless ($file);
    if (my $format = $self->_parse_filename( $file )) {
        return $self->format($format);
    }
    return undef;
}

*type = \&format;
sub format {
    my $self = shift;
    my $newval = lc(shift || '');
    if ($newval && $newval ne $self->{FORMAT}) {
        $self->close_input();
        $self->{OPENFILE}  = \&_open_file;
        $self->{CLOSEFILE} = \&_close_file;
        if ($newval =~ /^(3dtsv)$/) {
            $self->{FORMAT}   = '3dtsv';
            $self->{OPENFILE} = \&_open_3dtsv;
            $self->{NEXTROW}  = \&_nextrow_excel;
        } elsif ($newval =~ /^(tsv|txt|text|list)$/) {
            $self->{FORMAT}  = $newval =~ /^(tsv)$/ ? 'tsv' : 'list';
            $self->{NEXTROW} = \&_nextrow_tsv;
        } elsif ($newval =~ /^(vcf)$/) {
            $self->{FORMAT}  = 'vcf';
            $self->{NEXTROW} = \&_nextrow_tsv;
        } elsif ($newval =~ /^(gtf)$/) {
            $self->{FORMAT}  = 'gtf';
            $self->{NEXTROW} = \&_nextrow_gtf;
        } elsif ($newval =~ /^(csv)$/) {
            $self->{FORMAT}   = 'csv';
            $self->separator(',');
            $self->{NEXTROW} = \&_nextrow_csv;
        } elsif ($newval =~ /^(fa|faa|fna|fasta)$/) {
            $self->{FORMAT}   = 'fasta';
            $self->{NEXTROW} = \&_nextrow_fasta;
        } elsif ($newval =~ /^(fastq)$/) {
            $self->{FORMAT}   = 'fastq';
            $self->{NEXTROW} = \&_nextrow_fastq;
        } elsif ($newval =~ /^(rich|set)$/) {
            $self->{FORMAT}   = 'rich';
            $self->{OPENFILE} = \&_open_rich;
            $self->{NEXTROW}  = \&_nextrow_excel;
        } elsif ($newval =~ /^(xls|excel|xlsx)$/) {
        #    $self->{FORMAT}   = $newval =~ /xlsx/ ? 'xlsx' : 'excel';
        #    $self->{NEXTROW}  = \&_nextrow_excel;
        #    $self->{OPENFILE} = \&_open_excel;
        #    $self->{CLOSEFILE} = \&_close_excel;
        } elsif (! $_[0]) {
            $self->death("I do not know how to interpret format '$newval'");
        }
    }
    return $self->{FORMAT};
}

*file = \&input;
sub input {
    my $self     = shift;
    my ($newval) = @_;
    return $self->{INPUT} unless ($newval);
    unless ($self->format) {
        unless ($self->format_from_file_name( $newval )) {
            $self->death
                ("Unable to set input to '$newval'",
                 "Could not guess format from file name",
                 "Please provide format() explicitly");
            return $self->{INPUT};
        }
    }
    $self->close_input();
    if (-e $newval) {
        # The input is a file
        $self->{INPUTTYPE} = 'file';
        unless ($self->format) {
            $self->format_from_file_name($newval);
        }
        if ($self->{OPENFILE}) {
            &{$self->{OPENFILE}}($self, $newval);
        } else {
            $self->death("Could not guess file type from '$newval'");
        }
        $self->{INPUT} = $newval;
    } else {
        $self->death("I do not know how to interpret input '$newval'");
    }
    $self->{ROWCOUNT} = 0;
    delete $self->{STARTED};
    return $self->{INPUT};
}

sub metadata {
    my $self = shift;
    my ($tag, $val) = @_;
    return undef unless ($tag);
    $tag = uc($tag);
    if (defined $val) {
        $self->{METADATA}{$tag} = $val;
    }
    return $self->{METADATA}{$tag};
}

sub open_input {
    my $self = shift;
    $self->{METADATA} = {};
}

sub close_input {
    my $self = shift;
    $self->{HEADER} = [ ];
    $self->{SHEETS} = {
        active => undef,
        lookup => {},
        list   => [],
        row    => [],
    };
    if (my $meth = $self->{CLOSEFILE}) {
        &{$meth}($self);
    }
}

sub each_sheet {
    my $self = shift;
    my $sdat = $self->{SHEETS};
    return $sdat ? (1..($#{$sdat->{list}} + 1)) : ();    
}

*sheet = \&select_sheet;
sub select_sheet {
    my $self = shift;
    my $sdat = $self->{SHEETS};
    unless ($sdat) {
        $self->err("Can not select sheet when no data are present!");
        return wantarray ? () : undef;
    }
    if (my $req = shift) {
        my $num = $self->lookup_sheet( $req );
        if (defined $num) {
            $sdat->{active} = $num;
        } else {
            $self->msg("[ERR]", "Unrecognized sheet request '$req' ignored");
            return wantarray ? () : undef;
        }
    }
    my $act = $sdat->{active} || 0;
    my $rv  = $sdat->{list}[ $act ];
    return wantarray ? ($rv, $act) : $rv;
}

sub lookup_sheet {
    my $self = shift;
    my $req  = shift;
    return undef unless ($req);
    my $sdat = $self->{SHEETS};
    return undef unless ($sdat);
    my $num = $sdat->{lookup}{uc($req)};
}

sub sheet_name {
    my $self = shift;
    my $req  = shift;
    my $num  = 0;
    if ($req) {
        $num  = $self->lookup_sheet($req);
    } else {
        my $toss;
        ($toss, $num) = $self->select_sheet();
    }
    return "NO SHEET AVAILABLE" unless (defined $num);
    return $self->{SHEETS}{names}[$num] || "Sheet ".($num + 1);
}

*current_sheet_num = \&current_sheet_number;
sub current_sheet_number {
    my $self = shift;
    my $sdat = $self->{SHEETS};
    return $sdat ? $sdat->{active} : undef;
}

sub input_type {
    return shift->{INPUTTYPE};
}

*next_row = \&nextrow;
sub nextrow {
    my $self = shift;
    return shift @{$self->{PUSH}} if ($#{$self->{PUSH}} > -1);
    return undef if ($self->{LIMIT} && $self->{ROWCOUNT} &&
                     $self->{ROWCOUNT} >= $self->{LIMIT});
    my $meth = $self->{NEXTROW};
    unless ($meth) {
        $self->death
            ("You have not provided enough information to recover row data");
    }
    my $row;
    $self->{STARTED} ||= $self->{LASTPROG} = time;
    while (1) {
        $row = &{$meth}($self);
        last unless ($row);
        if ($self->{TOSS_FILTER} && &{$self->{TOSS_FILTER}}( $row, $self)) {
            $row = undef;
            next;
        }
        if ($self->{KEEP_FILTER} && !&{$self->{KEEP_FILTER}}( $row, $self)) {
            $row = undef;
            next;
        }
        $self->{ROWCOUNT}++;
        last;
    }
    if ($self->{VAL_MAP} && $row) {
        for my $i (0..$#{$row}) {
            my $val = $row->[$i];
            if (defined $val) {
                $row->[$i] = $self->{VAL_MAP}{$val} if
                    (exists $self->{VAL_MAP}{$val});
            } elsif (defined $self->{VAL_MAP}{'--UNDEF--'}) {
                $row->[$i] = $self->{VAL_MAP}{'--UNDEF--'};
            }
        }
    }
    return $row;
}

sub next_clean_row {
    my $self = shift;
    my $row = $self->nextrow();
    return $row unless ($row);
    # Remove non-ASCII characters from each cell
    # Remove leading and trailing whitespace from each cell
    map { s/\P{IsASCII}//g; 
          s/^\s+//; s/\s+$// } @{$row};
    while ($#{$row} != -1 && 
           (!defined $row->[-1] || $row->[-1] eq '')) {
        # Remove trailing blank cells
        pop @{$row};
    }
    return $row;
}

*next_hash = \&nexthash;
sub nexthash {
    my $self = shift;
    my $row  = $self->nextrow();
    return $self->_row_to_hash( $row );
}

sub next_clean_hash {
    my $self = shift;
    my $row  = $self->next_clean_row();
    return $self->_row_to_hash( $row );
}

sub _row_to_hash {
    my $self = shift;
    my $row  = shift;
    return undef unless ($row);
    my %hash;
    if (my $cols = $self->header()) {
        for my $c (0..$#{$row}) {
            my $cn = $cols->[$c] || "Column ".($c+1);
            next if ($self->{IGNORE_COL}{$cn});
            next if (defined $hash{$cn});
            $hash{$cn} = $row->[$c];
        }
    } else {
        %hash = map { $_ + 1 => $row->[ $_ ] } (0..$#{$row});
    }
    return \%hash;
}

our $tsv3dtok = '#>>SHEET>>';
our $tsv3dhead = '#>>HEADER>>';

sub export_as_3dtsv {
    my $self = shift;
    my $txt  = "";
    foreach my $s ($self->each_sheet()) {
        $self->select_sheet($s);
        my $sn = $self->sheet_name();
        $txt .= sprintf("%s %s\n", $tsv3dtok, $sn);
        my @head = $self->header();
        if ($#head != -1) {
            my $htxt = join("\t", map { defined $_ ? $_ : '' } @head);
            $txt .= sprintf("%s %s\n", $tsv3dhead, $htxt)
                unless ($htxt =~ /^\t*$/);
        }
        while (my $row = $self->next_clean_row()) {
            my $rtxt = join("\t", @{$row});
            $txt .= $rtxt."\n" unless ($rtxt =~ /^\t*$/);
        }
    }
    return $txt;
}


sub _open_3dtsv {
    my $self = shift;
    my ($fh, $sdat, $exd) = $self->_prepare_basic_workbook_properties( @_ );
    my $snum  = -1;
    my $sheet;
    while (<$fh>) {
        s/[\n\r]+$//;
        if (/^\Q$tsv3dtok\E (.+?)\s*$/) {
            # Sheet designation #>>
            $sheet = $sdat->{list}[++$snum] = {
                Name  => $1,
                Cells => [],
            };
        } elsif(/^\Q$tsv3dhead\E (.+?)\s*$/) {
            # Header designation
            my @head = split(/\t/, $1);
            $self->{HEADER}[$snum] = \@head;
            $self->has_header(1);
        } elsif ($sheet) {
            # Data, and a sheet to put it in
            my @row = split("\t");
            push @{$sheet->{Cells}}, \@row;
        }
    }
    close $fh;
    $self->_set_basic_workbook_properties();
}

sub _prepare_basic_workbook_properties {
    my $self = shift;
    my ($path) = @_;
    unless (-e $path) {
        $self->death("Can not open '$path' - failed to find file.");
    }
    # To get the sheets we will just parse the whole file
    my ($fh, $format, $coding) = $self->_filehandle_for_file( $path );
    $self->open_input();
    my $fid    = $self->{FILEDAT} = {
        path => $path,
        code => $coding,
        FH   => $fh,
    };
    my $sdat  = $self->{SHEETS}   = {
        list => [],
    };
    my $exd   = $self->{EXCELDAT} = {
        # wb     => $wb,
        path   => $path,
        sheets => [],
        row    => [],
        list   => [],
    };
    return ($fh, $sdat, $exd);
}

sub _set_basic_workbook_properties {
    my $self  = shift;
    my $sdat  = $self->{SHEETS};
    my $exd   = $self->{EXCELDAT};
    for my $snum (0..$#{$sdat->{list}}) {
        my $sheet = $sdat->{list}[$snum];
        my $cells = $sheet->{Cells};
        my ($maxC) = sort { $b <=> $a } map { $#{$_} } @{$cells};
        $sheet->{MaxCol} = $maxC;
        my $sinfo = $exd->{sheets}[$snum] = {
            row      => 0,
            rowcount => $#{$cells},
        };
        # Set the lookup keys
        $sdat->{lookup}{$snum + 1}  = $snum;
        $sdat->{lookup}{uc($sheet)} = $snum;
        if (my $wsn = $sheet->{Name}) {
            $sdat->{names}[$snum] = $wsn;
            $sinfo->{name}        = $wsn;
            $wsn = uc($wsn);
            $sdat->{lookup}{$wsn} = $snum;
            $wsn =~ s/[\s_]+//g;
            $sdat->{lookup}{$wsn} = $snum;
        }
    }
}

#sub _open_excel {
#    my $self = shift;
#    my ($path) = @_;
#    unless (-e $path) {
#        $self->death("Can not open '$path' - failed to find file.");
#    }
#    $self->open_input();
#    my $frm = $self->format();
#    my ($wb);
#    if ($frm eq 'xlsx') {
#        if (ref($path)) {
#            # This is a file handle. The XLSX module expects a very
#            # particular kind of file handle OBJECT, so we need to
#            # write this to disk and provide the file path instead
#            my $tmp = $self->{TEMP_FILE} = "/tmp/TableReader-$$.xlsx";
#            open(TRTMP, ">$tmp") || $self->death
#                ("Failed to write temporary file for XLSX file", $!, $tmp);
#            while (<$path> ) { print TRTMP $_; }
#            close TRTMP;
#            chmod(0666, $tmp);
#            $wb = Spreadsheet::XLSX->new($tmp);
#        } else {
#            $wb = Spreadsheet::XLSX->new($path);
#        }
#    } else {
#        my $pe = new Spreadsheet::ParseExcel;
#        $wb    = $pe->Parse($path);
#    }
#    my @sheet = @{$wb->{Worksheet} || []};
#    my $sdat  = $self->{SHEETS};
#    my $exd   = $self->{EXCELDAT} = {
#        wb     => $wb,
#        path   => $path,
#        sheets => [],
#        row    => [],
#        list   => [],
#    };
#    for my $snum (0..$#sheet) {
#        my $sheet = $sheet[$snum];
#        my $sinfo = $exd->{sheets}[$snum] = {
#            # sheet    => $sheet,
#            row      => 0,
#            rowcount => $#{$sheet->{Cells}},
#        };
#        $sdat->{list}[$snum] = $sheet;
#        if (my $wsn = $sheet->{Name}) {
#            $sdat->{names}[$snum] = $wsn;
#            $sinfo->{name}        = $wsn;
#            $wsn = uc($wsn);
#            $sdat->{lookup}{$wsn} = $snum;
#            $wsn =~ s/[\s_]+//g;
#            $sdat->{lookup}{$wsn} = $snum;
#        }
#        $sdat->{lookup}{$snum + 1}  = $snum;
#        $sdat->{lookup}{uc($sheet)} = $snum;
#        if (my $hnum = $self->has_header()) {
#            $self->select_sheet($snum + 1);
#            my $plim = $self->{LIMIT};
#            $self->{LIMIT} = 0;
#            for my $discard (2..$hnum) { $self->nextrow() }
#            my $hrow = $self->next_row();
#            $self->{LIMIT} = $plim;
#            $self->{ROWCOUNT} = 0;
#            my @head;
#            foreach my $val (@{$hrow}) {
#                push @head, $self->remap_header_name($val);
#            }
#            $self->{HEADER}[$snum] = \@head;
#        }
#        $sdat->{row}[$snum] = 0;
#    }
#    return $self->select_sheet(1);
#}

sub _close_excel {
    my $self = shift;
    my $exd = $self->{EXCELDAT};
    return 0 unless ($exd);
    $self->{EXCELDAT} = undef;
    return 1;
}

sub _parse_filename {
    my $self = shift;
    # Allow subroutine to be called without a blessed object:
    my $path = ref($self) ? shift : $self;
    return () unless ($path);
    my $raw    = lc($path);
    my $coding = 'text';
    my $format;
    if ($raw =~ /\.xlsx?$/) {
        ($format, $coding) = ($raw =~ /\.xlsx$/ ? 'xlsx' : 'excel', 'binary');
    } elsif ($raw =~ /^(.+)\.(gzip|gz)$/) {
        ($raw, $coding) = ($1, 'gzip');
    } elsif ($raw =~ /^(.+)\.(bzip2|bz2)$/) {
        ($raw, $coding) = ($1, 'bzip2');
    }
    unless ($format) {
        if ($raw =~ /\.(3dtsv)$/) {
            $format = '3dtsv';
        } elsif ($raw =~ /\.(tsv)$/) {
            $format = 'tsv';
        } elsif ($raw =~ /\.(gtf)$/) {
            $format = 'gtf';
        } elsif ($raw =~ /\.(list|txt|text)$/)  {
            $format = 'list';
        } elsif ($raw =~ /\.(fa|fasta)$/)  {
            $format = 'fasta';
        } elsif ($raw =~ /\.(fastq)$/)  {
            $format = 'fastq';
        } elsif ($raw =~ /\.(rich|set)$/)  {
            $format = 'rich';
        } elsif ($raw =~ /\.(csv)$/)  {
            $format = 'csv';
        } elsif ($raw =~ /\.(xlsx)$/)  {
            $format = 'xlsx';
        } elsif ($raw =~ /\.(xls)$/)  {
            $format = 'excel';
        }
    }
    return wantarray ? ($format, $coding) : $format;
}

sub _filehandle_for_file {
    my $self = shift;
    my ($path) = @_;
    my $rp = ref($path);
    return ($path) if ($rp eq 'Fh');
    unless (-e $path) {
        $self->death("Can not open '$path' - failed to find file.");
    }
    my ($format, $coding) = $self->_parse_filename($path);
    my $fh;
    my $handleName = sprintf("HANDLE_%d", ++$GlobalHandleCounter);
    my ($codeTxt, $opType) = ("open($handleName, \"","");
    if ($coding eq 'gzip') {
        $opType   = "gunzip pipe";
        open($fh, "gunzip -c \"$path\" |") || $self->death
            ("Failed to open $opType", $path, $!);
    } elsif ($coding eq 'bzip2') {
        open($fh, "bunzip2 -c \"$path\" |") || $self->death
            ("Failed to open $opType", $path, $!);
    } else {
        open($fh, "<$path") || $self->death
            ("Failed to open $opType", $path, $!);
        $opType   = "read handle";
    }
    unless ($fh) {
        $self->death("Failed to get filehandle via eval", $codeTxt);
    }
    return wantarray ? ($fh, $format, $coding) : $fh;
}

sub _open_file {
    my $self = shift;
    my ($path) = @_;
    my ($fh, $format, $coding) = $self->_filehandle_for_file( $path );
    $self->open_input();
    if (my $preset = $self->format) {
        $format = $preset;
    } else {
        if ($format) {
            $self->format($format);
        } else {
            $self->death("I can not guess the file format for '$path'. ".
                         "Please explicitly specify it with format().");
        }
    }
    my $fid    = $self->{FILEDAT} = {
        path => $path,
        code => $coding,
        FH   => $fh,
    };

    if (my $meth = $self->scan_until()) {
        # The user wants to ignore stuff at the front of the file
        while (my $line = $self->_next_line()) {
            if ( my $fnd = &{$meth}( $line ) ) {
                # Ok, we found a match. Put it back and stop scanning
                $self->_push_line($line);
                last;
            } else {
                push @{$self->{SCAN_REJECT}}, $line;
            }
        }
    }

    if ($format eq 'csv') {
        my $quote = $self->quotes();
        unless ($quote) {
            my @quotes = ('"', "'");
            # See if we can figure out quoting
            # Get 10 sample rows
            my (%counts, @replace);
            for my $sr (1..10) {
                if (my $line = $self->_next_line()) {
                    push @replace, $line;
                    foreach my $qt (@quotes) {
                        my $hack = $line;
                        my $num  = 0;
                        while ($hack =~ /($qt\,$qt)/) {
                            my $qm = $1;
                            $hack =~ s/\Q$qm\E//;
                            $num++;
                        }
                        $counts{$qt} += $num if ($num);
                    }
                }
            }
            # Make sure the tested lines go back on the stack:
            $self->_push_line( @replace );
            ($quote) = sort { $counts{$b} <=> $counts{$a} } keys %counts;
            $quote = [$quote] if ($quote);
        }
        $fid->{QUOTES} = $quote || [];
    } elsif ($format eq 'gtf') {
        # Look for file attributes
        my $plim = $self->{LIMIT};
        $self->{LIMIT} = 0;
        while (my $line = $self->_next_line()) {
            if ($line =~ /^\#!(\S+)\s+(.+)/) {
                my ($k, $v) = ($1, $2);
                $v =~ s/[\n\r]+$//;
                $self->{FILEDAT}{FILE_ATTR}{$k} = $v;
            } else {
                $self->_push_line( $line );
                last;
            }
        }
        $self->{LIMIT} = $plim;
        $self->{ROWCOUNT} = 0;
    } elsif ($format eq 'vcf') {
        # We need to read off the information at the top
        # http://www.1000genomes.org/node/101
        my $lastCom;
        my $plim = $self->{LIMIT};
        $self->{LIMIT} = 0;
        while (my $row = $self->nextrow() ) {
            if ($row->[0] =~ /^(\#+)(.+)/) {
                my ($com, $dat) = ($1, $2);
                $row->[0] = $dat;
                # May want to parse these later, so store them:
                push @{$self->{FILEDAT}{FULL_HEADERS}}, $dat;
                $lastCom  = $row;
            } else {
                $self->_push_line( join("\t", @{$row}) );
                last;
            }
        }
        $self->{LIMIT} = $plim;
        $self->{ROWCOUNT} = 0;
        if ($lastCom) {
            $self->has_header( 1 );
            $self->_unshift( $lastCom );
        } else {
            $self->death("Failed to identify the header row");
        }
    } elsif ($format eq 'rich') {
        # Read the first row just to trigger capture of initial metadata
        $self->_push( $self->nextrow() );
        $self->has_header( 0 );
    }
    my $saveLimit = $self->{LIMIT};
    $self->{LIMIT} = 0;
    if ( $self->has_header() ) {
        my $hrow = $self->next_row();
        my @head;
        if ($format eq 'vcf') {
            # Find the first genotype column
            my $fd   = $self->{FILEDAT} ||= {};
            my %stnd = map { uc($_) => 1 } 
            qw(CHROM POS ID REF ALT QUAL FILTER INFO FORMAT);
            my @geno;
            my $targ = \@head;
            for my $i (0..$#{$hrow}) {
                my $col = $hrow->[$i];
                if ($col eq 'FORMAT') {
                    $fd->{FORMATINDEX} = $i;
                }
                if ($stnd{$col}) {
                    $self->death("Standard column '$col' found after unexpected column '$targ->[-1]'") if ($fd->{GENOINDEX});
                } else {
                    unless ($fd->{GENOINDEX}) {
                        $fd->{GENOINDEX} = $i;
                        $self->death("Unexpected column '$col' found at front of file")
                            unless ($i);
                        $self->death("Presumptive genotype column '$col' found without preceeding 'FORMAT' column")
                            unless ($fd->{FORMATINDEX});
                        push @head, $self->remap_header_name("GENOTYPES");
                    }
                    $targ = \@geno;
                }
                push @{$targ}, $self->remap_header_name($col);
            }
            $fd->{GENOTYPE_NAMES} = \@geno;
            $self->{NEXTROW} = \&_nextrow_vcf;
        } else {
            foreach my $val (@{$hrow}) {
                push @head, $self->remap_header_name($val);
            }
        }
        # PROBLEM? do we need to index this to [0] ?
        $self->{HEADER}[0] = \@head;
        # $self->{HEADER}   = [ $self->nextrow() ];
    }
    $self->{LIMIT} = $saveLimit;
    $self->{ROWCOUNT} = 0;
    $self->{SHEETS} = {
        active => 0,
        lookup => { 1 => 0, uc($path) => 0 },
        list   => [ $fid->{FH} ],
        row    => [ 0 ],
    };
    return $fid->{FH};
}

sub _close_file {
    my $self = shift;
    my $fid  = $self->{FILEDAT};
    return 0 unless ($fid);
    my $fh   = $self->{FH};
    return 0 unless ($fh);
    close $fh;
    $self->{FILEDAT} = undef;
    return 1;
}

sub _nextrow_tsv {
    my $self = shift;
    # my $fh   = $self->{FILEDAT}{FH};
    # return undef unless ($fh);
    my $row  = $self->_next_line();
    unless ($row) {
        $self->_close_file();
        return undef;
    }
    $row =~ s/[\n\r]+$//;
    return [ split(/\t/, $row) ];
}

# http://mblab.wustl.edu/GTF22.html
sub _nextrow_gtf {
    my $self = shift;
    # my $fh   = $self->{FILEDAT}{FH};
    # return undef unless ($fh);
    my $row;
    while (1) {
        $row  = $self->_next_line();
        if (!$row) {
            $self->_close_file();
            return undef;
        } elsif ($row =~ /^\#/) {
            # Skip comments
            next;
        }
        last;
    }
    $row =~ s/[\n\r]+$//;
    my @cols = split(/\t/, $row);
    my $rv = {
        chr  => $cols[0],
        src  => $cols[1],
        feat => $cols[2],
        s    => $cols[3],
        e    => $cols[4],
        sc   => $cols[5],
        str  => $cols[6],
        frm  => $cols[7],
    };
    # Need comment handling
    my $attr = $rv->{attr} = {};
    my $atxt = $cols[8] || "";
    while ($atxt =~ /^(\s*(\S+)\s+\"([^\"]+)";\s*)/ ||
           $atxt =~ /^(\s*(\S+)\s+([^;\#]+);\s*)/) {
        my ($rep, $t, $v) = ($1, $2, $3);
        $atxt =~ s/\Q$rep\E//;
        push @{$attr->{$t}}, $v;
    }
    
    return $rv;
}

sub _nextrow_vcf {
    my $self = shift;
    my $row  = $self->_nextrow_tsv() || return undef;
    if (my $gi = $self->{FILEDAT}{GENOINDEX}) {
        # Break out the genotype data
        my $fd     = $self->{FILEDAT};
        my @newRow = map { $row->[$_] } (0..($gi-1));
        my $fmt    = $row->[$fd->{FORMATINDEX}];
        my @fields = $fmt ? split(':', $fmt ) : ();
        my $geno   = $newRow[$gi] = [];
        my $gNames = $fd->{GENOTYPE_NAMES};
        for my $i ($gi..$#{$row}) {
            my $dat  = { name => $gNames->[ $i - $gi ] || "Genotype".($i+1)};
            push @{$geno}, $dat;
            my $fieldDat = $row->[$i];
            # Some VCF files (eg MGP v3) are putting a zero ("0") for "no data"
            # Skip those:
            next unless ($fieldDat);
            my @bits = split(':', $fieldDat);
            for my $j (0..$#bits) {
                $dat->{ $fields[$j] || $j+1 } = $bits[$j];
            }
        }
        $row = \@newRow;
    }
    return $row;
}

sub _open_rich {
    my $self = shift;
    my ($fh, $sdat, $exd) = $self->_prepare_basic_workbook_properties( @_ );
    my $snum  = -1;
    my $sheet;
    while (<$fh>) {
        s/[\n\r]+$//;
        # Skip fully blank lines
        next if (/^\s*$/);
        if (/^\s*\#\s*(.*)/) {
            # fully commented row
            my $com = $1 || "";
            if ($com =~ /(\S+)\s*[\:\=]\s*(.+)\s*$/) {
                $self->metadata( $1, $2 );
            } elsif ($com =~ /LIST\s*\-\s*(.+?)\s*$/) {
                $sheet = $sdat->{list}[++$snum] = {
                    Name  => $1,
                    Cells => [],
                };
            } elsif ($com) {
                $self->{LastRichCom} = $com;
            }
            next;
        }
        # Ok, the line is neither blank nor commented, so it is data
        if (my $headTxt = $self->{LastRichCom}) {
            # It looks like we had a header name row previously
            $self->has_header(1);
            $self->{HEADER}[$snum] = [ split(/\s*\t\s*/, $headTxt) ];
            $self->{LastRichCom} = undef;
        }
        # Exclude trailing comments
        s/\#.+//;
        s/^\s+//;
        s/\s+$//;
        my @row = split(/\s*[\t]\s*/);
        push @{$sheet->{Cells}}, \@row;
    }
    close $fh;
    $self->_set_basic_workbook_properties();
}

sub _nextrow_rich_CAN_DISCARD {
    my $self = shift;
    #my $fh   = $self->{FILEDAT}{FH};
    #return undef unless ($fh);
    my @row;
    while (my $line = $self->_next_line()) {
        $line =~ s/[\n\r]+$//;
        next if ($line =~ /^\s*$/);
        if ($line =~ /^\s*\#\s*(.*)/) {
            # fully commented row
            my $com = $1 || "";
            if ($com =~ /(\S+)\s*[\:\=]\s*(.+)\s*$/) {
                $self->metadata( $1, $2 );
            } elsif ($com =~ /LIST\s*\-\s*(\S+)/) {
                # The name of the list - we should capture this somewhere


                # NEED TO TREAT THESE AS MULTI-SHEET DOCUMENTS!!!!


            } elsif ($com) {
                $self->{LastRichCom} = $com;
            }
            next;
        }
        if (my $headTxt = $self->{LastRichCom}) {
            my $snum = 0; # NEEDS TO APPLY TO ACTUAL SHEET NUMBER
            $self->{HAS_HEADER} = 1;
            $self->{HEADER}[1] = [ split(/\t/, $headTxt) ];
            $self->{LastRichCom} = undef;
        }
        # Exclude trailing comments
        $line =~ s/\#.+//;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        @row = split(/\s*[\t]\s*/, $line);
        last;
    }
    return \@row if (defined $row[0]);
    $self->_close_file();
    return undef;
}

sub _nextrow_fasta {
    my $self = shift;
    # my $fh   = $self->{FILEDAT}{FH};
    # return undef unless ($fh);
    # my $row = $self->{FILEDAT}{FASTA_HEADER} || [];
    # delete $self->{FILEDAT}{FASTA_HEADER};
    my $row;
    while (my $line = $self->_next_line()) {
        $line =~ s/[\n\r]+$//;
        next if ($line =~ /^\s*$/);
        if ($line =~ /^\>(\S+)\s+(\S.*)$/ || 
            $line =~ /^\>(\S+)\s*$/) {
            # A fasta header
            if ($row) {
                # We already have the header for this entry, so we
                # have reached the next sequence. We need to hold onto
                # this header for the next entry
                $self->_push_line( $line );
                last;
            } else {
                # This must be the first entry encountered in the file
                $row = [ $1, defined $2 ? $2 : "", "" ];
            }
        } else {
            # Presumably sequence data
            if ($row) {
                # Good, we have an id, extend sequence. We are not cleaning it
                $row->[2] .= $line;
            } else {
                # oops. The file did not begin with a fasta header
                $self->err("File does not begin with a fasta header",
                           $self->input, "First line: '$line'");
                $row = [];
                last;
            }
        }
    }
    return $row if ($row);
    $self->_close_file();
    return undef;
}

sub _nextrow_fastq {
    my $self = shift;
    # my $fh   = $self->{FILEDAT}{FH};
    # return undef unless ($fh);
    # my $row = $self->{FILEDAT}{FASTA_HEADER} || [];
    # delete $self->{FILEDAT}{FASTA_HEADER};
    my $row;
    while (my $line = $self->_next_line()) {
        $line =~ s/[\n\r]+$//;
        if ($line =~ /^\@(\S+)\s*(.+)/ || 
            $line =~ /^\@(\S+)\s*$/) {
            $row      = [$1, defined $2 ? $2 : "" ];
            my $seq   = $self->_next_line() || "";
            $seq      =~ s/[\n\r]+$//;
            $self->_next_line();
            my $qual  = $self->_next_line() || "";
            $qual     =~ s/[\n\r]+$//;
            push @{$row}, ($seq, $qual);
            last;
        } else {
            $self->err("Unexpected line in FASTQ file", $line);
        }
    }
    return $row if ($row);
    $self->_close_file();
    return undef;
}

sub _nextrow_csv {
    my $self = shift;
    # my $fh   = $self->{FILEDAT}{FH};
    # return undef unless ($fh);
    my $row  = $self->_next_line();
    unless ($row) {
        $self->_close_file();
        return undef;
    }
    $row =~ s/[\n\r]+$//;
    my @quoted;
    foreach my $qt (@{$self->{FILEDAT}{QUOTES}}) {
        while ($row =~ /($qt([^$qt]*)$qt)/) {
            my ($out, $in) = ($1, $2);
            push @quoted, [$out, $in];
            my $rep = "QUOTED{$#quoted}";
            $row =~ s/\Q$out\E/$rep/g;
        }
    }
    # ARG. Nested quotes in some data
    # eg:  1,2,""foo"",3
    # Very non-Kosher, but found in comments in some pseudo-CSV files
    my $keepGoing = 0;
    do {
        $keepGoing = 0;
        for my $i (0..$#quoted) {
            if ($quoted[$i][0] =~ /(QUOTED{(\d+)})/) {
                my ($orig, $rep) = ($1, $quoted[$2][0]);
                $quoted[$i][0] =~ s/\Q$orig\E/$rep/g;
                $keepGoing++;
            }
        }
    } while ($keepGoing);
    my @rv;
    my $sep = $self->separator();
    foreach my $txt (split(/\Q$sep\E/, $row)) {
        if ($txt =~ /^QUOTED{(\d+)}$/) {
            # The entire cell is quoted, we will just leave out the quotes
            $txt = $quoted[$1][1];
        } else {
            while ($txt =~ /(QUOTED{(\d+)})/) {
                # Just an internal part is quoted
                my ($orig, $rep) = ($1, $quoted[$2][0]);
                $txt =~ s/\Q$orig\E/$rep/g;
            }
        }
        push @rv, $txt;
    }
    return \@rv;
}

sub _nextrow_excel {
    my $self = shift;
    my $exd  = $self->{EXCELDAT};
    unless ($exd) {
        $self->err("Can not get excel rows without data!");
        return undef;
    }
    my ($ws, $snum) = $self->select_sheet();
    unless ($ws) {
        $self->err("Can not get excel rows without an active sheet!");
        return undef;
    }
    my $sinfo = $exd->{sheets}[$snum];
    my $r = $sinfo->{row}++;
    return undef if ($r > $sinfo->{rowcount});
    my @row;
    for my $c (0..$ws->{MaxCol}) {
        my $val = &cellval( $ws->{Cells}[$r][$c] );
        push @row, $val;
    }
    return \@row;
}

sub _next_line {
    my $self = shift;
    return shift @{$self->{PUSH_LINE}} unless ($#{$self->{PUSH_LINE}} == -1);
    my $fh   = $self->{FILEDAT}{FH};
    return undef unless ($fh);
    return <$fh>;
}

sub cellval {
    my ($cell) = @_;
    if (!defined $cell) {
        return '';
    } elsif (ref($cell)) {
        return (defined $cell->{Val}) ? $cell->{Val} : "";
    } else {
        return $cell;
    }
}

sub random_access {
    my $self = shift;
    return BMS::TableReader::RandomAccess->new
        ( -tablereader => $self,
          @_ );
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
package BMS::TableReader::RandomAccess;
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

use BMS::Utilities;
use vars qw(@ISA);
@ISA      = qw(BMS::Utilities);

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {
    };
    bless ($self, $class);
    my $args = $self->parseparams( @_ );
    my $tr   = $args->{TR} || $args->{READER} || $args->{TABLEREADER};
    my @data;
    my @sheets = $tr->each_sheet();
    for my $s (0..$#sheets) {
        my $sheet = $sheets[$s];
        $tr->select_sheet($sheet);
        my $sn    = $tr->sheet_name();
        my @head  = $tr->header();
        my $sdat  = $data[$s] = {
            name  => $sn,
            snum  => $s + 1,
            data  => [],
            head  => \@head,
        };
        my $darr    = $sdat->{data};
        my $maxCol  = -1;
        my $trimCol = $args->{TRIMCOL};
        while (my $row = $tr->next_clean_row()) {
            if ($#{$row} > $maxCol) {
                if ($trimCol) {
                    # Remove trailing empty cells
                    while ($#{$row} > -1 && (!defined $row->[-1] ||
                                             $row->[-1] eq '')) {
                        pop @{$row};
                    }
                    $maxCol = $#{$row} if ($#{$row} > $maxCol);
                } else {
                    $maxCol = $#{$row};
                }
            }
            push @{$darr}, $row;
        }
        $sdat->{MaxCol} = $maxCol;
        my $ss = $data[$s] = 
            BMS::TableReader::RandomAccess::SimpleSheet->new( $sdat );
    }
    $self->{DATA} = \@data;
    return $self;
}

sub each_sheet {
    my $self = shift;
    my $rv   = $self->{DATA};
    return wantarray ? @{$rv} : $rv;
}

sub sheet {
    my $self = shift;
    my ($req) = @_;
    return wantarray ? () : undef unless (defined $req);
    my $si = $self->{SINDEX};
    unless ($self->{SINDEX}) {
        $si = $self->{SINDEX} = {};
        foreach my $sheet ($self->each_sheet()) {
            map { push @{$si->{uc($_)}}, $sheet } map
            { $sheet->{$_} || "" } qw(snum name);
        }
        delete $si->{""};
    }
    my $arr = $si->{uc($req)} || [];
    return @{$arr} if wantarray;
    return $#{$arr} == 0 ? $arr->[0] : undef;
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
package BMS::TableReader::RandomAccess::SimpleSheet;
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = shift;
    bless ($self, $class);
    return $self;
}

sub name { return shift->{name}; }
sub sheet_number { return shift->{snum}; }
# Zero indexed array boundaries:
sub maxcol { return shift->{MaxCol}; }
sub maxrow { return $#{shift->{data}}; }

*cells  = \&data;
*grid   = \&data;
sub data {
    my $self = shift;
    my $rv   = $self->{data};
    return wantarray ? @{$rv} : $rv;
}

*head = \&header;
sub header {
    my $self = shift;
    my $rv   = $self->{head};
    return wantarray ? @{$rv} : $rv;
}
