#!/usr/bin/env perl
##!/usr/bin/perl -w
# Author: Charles Tilford
# 6/12/2017: xw removed reliance on bioperl
# 6/9/2018: xw added title and description; edited sequence key.
use strict;
use JSON;
use FindBin qw($Bin);
use lib $Bin;
use BMS::TableReader;
use BMS::ArgumentParser;
#use Bio::PrimarySeq;

my $args = BMS::ArgumentParser->new
    ( -nocgi      => $ENV{HTTP_HOST} ? 0 : 1,
      -errormail  => 'charles.tilford@bms.com',
      -tmpdir     => "/tmp",
      noflags     => 1,
      -perc       => 1,
      -paramalias => {
          file       => [qw(input path)],
          perc       => [qw(percent)],
          noflag     => [qw(noflags)],
          xxxx       => [qw()],
          xxxx       => [qw()],
          xxxx       => [qw()],
      },
    );

my $nocgi     = $args->val(qw(nocgi));
if ($nocgi) {
    $args->shell_coloring();
} else {
    $args->set_mime( -mail => $args->val('errmail'), );
}

my $minPerc   = $args->val('perc');
my $noFlags   = $args->val('noflags');
my $fh        = *STDOUT;
my $source    = {};
my $cjs       = encode_json( &cx_panel_settings() );
my $ejs       = encode_json( &cx_callbacks() );
my $counter   = 0;
my $wid       = 1000;
my $hgt       = 100;
my $alnBlkSz  = 50;

my $trackCol = {
    WT  => "51,102,0",
    Del => "255,51,51",
    Ins => "0,0,204",
    CPX   => "96,0,96",
    Guide => "255,51,255",
};

my $allowedAliases = {
    Wildtype  => 'WT',
    Insertion => 'Ins',
    Deletion  => 'Del',
    Complex   => 'CPX',
    Guide     => 'Guide',
};

foreach my $path ($args->each_split_val('/\s*[\n\r\,]+\s*/','file')) {
    &read_source( $path );
}

=pod

$source will end up bing a hash structured as:

      {FPR1-CR2_S18} => Hash with 1 key HASH(0xf6ebc70)
        {FPR1_52250043} => Array with 12 elements ARRAY(0xf6ebca0)
          [ 0] = Hash with 11 keys HASH(0xf4c96b0)
            {Frame} => 0
            {Loc} => [52250026,52250036],[52250047,52250061]
            {Mut} => GCCGTGGCTG
            {Num} => 1783
            {Perc} => 6.91
            {Pos} => 52250046
            {Sample} => FPR1-CR2_S18
            {Seq} => AGTTACCTGAACCTGACTTCTGTTTC
            {Site} => FPR1_52250043
            {Str} => -
            {Type} => Del
          [ 1] = Hash with 11 keys HASH(0xf0264d0)
            {Frame} => 0
            {Loc} => [52250026,52250038],[1],[52250039,52250061]
            {Mut} => C
                        etc

=cut

my @samples = sort keys %{$source};
if ($#samples == -1) {
    #$args->msg("[?]","Provide input file with -input");
	$args->msg("No data in input file");
    exit;
}

print $fh &HTML_START();
print $fh "<h1>Alignment View of Insertion and Deletion Alleles in CDS</h1>
<p>
This is an interactive alignment view of the CDS (coding sequence) of sgRNA guide,
 WT (non-indel), and indel alleles in the gene. The frequencies of WT, deletion and
 insert reads are shown. Point mutations in reads were not represented here.
 The CDS sequences before and after indels were reconstructed from reference CDS. The
 bars can be zoomed in and out, and moved to the left and right. Intronic bases, if
 present in sgRNA sequence or deleted bases, will not be drawn. Deletion is shown as
 an arc line connecting neighboring bases. Insertion is shown as a small tick mark
 between two bases. Please note: the amino acid sequence at or after the insertion 
 was left unchanged from the wild type, due to technical issues. However, the inserted 
 bases and resulting amino acid sequence are shown in the pop-up window.
<p>
";

foreach my $sample (@samples) {
    foreach my $site (sort keys %{$source->{$sample}}) {
        &cx_panel( $source->{$sample}{$site} );
    }
}

print $fh &html_key();
print $fh &HTML_END();

sub dealias {
    my $val = shift;
    return $val unless (defined $val);
    return $allowedAliases->{$val} || $val;
}

sub cx_panel {
    my $all = shift;
    return if (!$all || $#{$all} == -1);
    my @muts = sort { $b->{Class} <=> $a->{Class} ||
                          $b->{Perc} <=> $a->{Perc} } @{$all};
    my $sample = $muts[0]{Sample};
    my $site   = $muts[0]{Site};
    my $cid    = sprintf("CrispCX%d", ++$counter);

    # Pre-scan mutation records to collect some aggregate data
    my $perInDel = 0;
    my ($wtDNA, $wtPrt) = ("", "");
    my %flags;
    my $stopCounter = 0;
    foreach my $mut (@muts) {
        my $perc = $mut->{Perc} || 0;
        my $clas = $mut->{Class};
        my $frm = $mut->{Frame};
        my $seq = $mut->{Seq};
        if ($seq && defined $frm) {
            # We can translate the reference
            #my $dBS = Bio::PrimarySeq->new
            #    (-seq => substr($seq, $frm), -alphabet => 'dna');
            #my $pBS = $dBS->translate();
            my $protseq = translate($seq); 
            my $pad = (" " x $frm) || "";
           	 
            # $ps will be a space-padded (for frame / offset) and
            # square-bracketted (to bring modulus-3 inline with DNA)
            # protein sequence.
            
            #my $ps = $pad .  #    join('', map { "[$_]" } split('', uc($pBS->seq())));
            my $ps = $pad . join('', map { "[$_]" } split('', $protseq));
            if ($ps =~ /^([^\*]+\*\])(.+)/) {
                my ($prot, $pastStop) = ($1, $2);
                $mut->{hasStop} = 1;
                # Lower-case amino acids after the stop:
                $ps = $prot . lc($pastStop);
                delete $flags{"EarlyStops=".$stopCounter};
                $flags{"EarlyStops=".++$stopCounter} = 'qry';
            }
            $mut->{ProtSeq} = $ps;
            if ($clas == 1) {
                # Make note of wild type for later comparisons
                if (! $wtPrt) {
                    $wtPrt = $ps;
                } elsif ($ps ne $wtPrt) {
                    warn "Multiple translations provided for WT sequence!\n".
                        "  $wtPrt (used)\n  $ps\n";
                }
            }
        }
        if ($clas == 1) {
            # WT
            if ($perc >= 5) {
                # Wild Type alleles are present. Not good.
                $flags{sprintf("Wild Type %d%%", $perc)} = 'del';
            }
            if (! $wtDNA) {
                $wtDNA = $seq;
            } elsif ($seq ne $wtDNA) {
                warn "Multiple DNA sequences provided for WT!\n".
                    "  $wtDNA (used)\n  $seq\n";
            }

        }
        next unless ($perc);
        next if ($clas);
        # InDel
        $perInDel += $perc;
        my $len = $mut->{MutLen};
        if (my $mseq = $mut->{Mut}) {
            my $ml = CORE::length($mseq);
            $args->msg("[?]", "Mutation sequence and length disagree",
                       "$sample : $ml vs $len bp") if ($len && $ml != $len);
            $len = $ml;
        }
        if ($len) {
            $mut->{CalcLen} = $len;
            unless ($len % 3) {
                $flags{sprintf("In-frame %dbp %s", $len, 
                                  $mut->{TypeShown} || "Unknown")} = 'del';
            }
        }
    }
    my ($wtLenD, $wtLenP) = map { CORE::length($_) } ($wtDNA, $wtPrt);
    $flags{sprintf("%d%% InDel", $perInDel)} = $perInDel < 95 ? "del" : "qry";
    printf( $fh "<h2>%s : %s", $sample, $site);
    %flags = () if ($noFlags);
    foreach my $fb (sort keys %flags) {
        printf($fh " <span class='%s'>%s</span>", $flags{$fb}, $fb);
    }
    print $fh "</h2>\n";
    print $fh "<canvas id='$cid' width='$wid' height='$hgt'></canvas>\n";
    my $dataData = { 
        tracks => [ ],
    };
    my $tracks = $dataData->{tracks} = [];
    my $track  = {
        type    => 'box',
        connect => 'true',
        trackType => 'CRISPR',
        honorType => 1,
    };
    push @{$tracks}, $track;
    my $tdata   = $track->{data} = [];
    my $rejects = 0;
    foreach my $mut (@muts) {
        my $loc = $mut->{Loc};
        my $perc = $mut->{Perc};
        my $clas = $mut->{Class};
        if ($minPerc && !$clas && (!$perc || ($perc < $minPerc))) {
            $rejects++;
            next;
        }
        unless ($loc) {
            $args->msg("[!!]", "No location provided for $sample/$site");
            next;
        }
        my $srcSeq = $mut->{Seq};
        my $srcPrt = $mut->{ProtSeq} || "";
        my @hspDat;
        if ($loc =~ /^\s*\[\s*(.+?)\s*\]\s*$/) {
            @hspDat = map { [ split(/\s*,\s*/, $_) ] } 
            split(/\s*\]\s*,\s*\[\s*/, $1);
        } else {
            $args->msg("[!!]", "Unrecognized location for $sample/$site",
                       $loc);
            next;
        }
        my $str = !$mut->{Str} ? 'right' : 
            $mut->{Str} =~ /^\-/ ? 'left' : 'right';
        # Xuning says that strand is just for information only
        # He will always give me the +1/Fwd/Top representation
        $str = 'right';
        my $off = 0;
        my $seqs = {
            show => "",
            dna  => "",
            prt  => "",
            dnaW => "",
            prtW => "",
        };
        
        my (@data, $insBlock);
        my $parseErr = "!!PARSE ERROR!!";

        my $lastRef = 0;
        for my $i (0..$#hspDat) {
            my @hsp = map { $_ + 0 } @{$hspDat[$i]};
            if ($#hsp == 1) {
                # Normal [s,e] HSP
                push @data, \@hsp;
                my ($s, $e) = @hsp;
                if ($i) {
                    # Not the first HSP
                    my $glen = $s - $lastRef - 1;
                    if ($glen > 0) {
                        # We are missing part of the reference
                        my $gap        = '-' x $glen;
                        $seqs->{prt}  .= $gap;
                        $seqs->{dna}  .= $gap;
                        $seqs->{dnaW} .= $lastRef < $wtLenD ? 
                            substr($wtDNA, $lastRef, $glen) : " " x $glen
                            if ($wtDNA);
                        $seqs->{prtW} .= $lastRef < $wtLenP ? 
                            substr($wtPrt, $lastRef, $glen) : " " x $glen
                            if ($wtPrt);
                    } elsif ($glen < 0) {
                        # Should not happen
                        $args->msg("[!!]", "Weird negative gap");
                        map { $seqs->{$_} .= $parseErr } keys %{$seqs};
                        next;
                    }
                }
                $lastRef       = $e;
                my $len        = $e - $s + 1;
                my $subDna     = substr($srcSeq, $off, $len);
                $seqs->{prt}  .= substr($srcPrt, $off, $len);
                $seqs->{dna}  .= $subDna;
                $seqs->{show} .= $subDna;
                $seqs->{dnaW} .= $s > $wtLenD ? " " x $len :
                    substr($wtDNA, $s-1, $len) if ($wtDNA);
                $seqs->{prtW} .= $s > $wtLenP ? " " x $len :
                    substr($wtPrt, $s-1, $len) if ($wtPrt);
                $off += $len;
                next;
            } elsif ($#hsp != 0) {
                # Should not happen
                $args->msg("[!!]", "Unexpected HSP", join(',', @hsp));
                map { $seqs->{$_} .= $parseErr } keys %{$seqs};
                next;
            }
            # A single value indicates an insertion
            if (!$i || $i == $#hspDat) {
                # We can not do anything here.
                $args->msg("[!!]","Insertion blocks are not allowed at the start or end of a location definition!");
                map { $seqs->{$_} .= $parseErr } keys %{$seqs};
                next;
            }
            my $s = $hspDat[$i-1][1];
            my $e = $hspDat[$i+1][0];
            my $len = $hsp[0];
            my $subDna     = substr($srcSeq, $off, $len);
            $seqs->{prt}  .= substr($srcPrt, $off, $len);
            $seqs->{dna}  .= $subDna;
            my $gap        = '-' x $len;
            $seqs->{dnaW} .= $gap;
            $seqs->{prtW} .= $gap;
            # Until insertion representation is fixed in CX, we can not
            # put the real sequence into the track:
            # $seqs->{show} .= $subDna;
            # Use a separate block instead:
            $insBlock ||= {
                label => "INS",
                name  => "INS",
                data  => [],
                fill  => "#ff0000",
                type  => 'Deletion',
                insertion => 1,
                dir   => $str,
                w     => 0,
                sequence => "",
            };
            push @{$insBlock->{data}}, [$s, $e];
            $insBlock->{sequence} .= $subDna;
            $off += $len;
        }
        my @alnBlk = ([]);
        my $aPos    = 0;
        my $aLen    = CORE::length($seqs->{dna});
        my @typs    = ('dna', 'prt');
        for my $j (0..$#typs) {
            my $typ    = $typs[$j];
            my $mutSeq = $seqs->{$typ};
            next unless ($mutSeq);
            my $mlen = CORE::length($mutSeq);
            my $wtSeq  = $seqs->{$typ.'W'};
            my $lastCls = "$typ";
            for (my $i = 0; $i < $mlen; $i++) {
                my $row = $alnBlk[int($i/$alnBlkSz)] ||= [];
                $row->[$j] ||= "<span class='$lastCls'>";
                # warn "$typ [$i] vs ($aLen)".CORE::length($mutSeq) unless ($i < CORE::length($mutSeq));
                my $char = substr($mutSeq, $i, 1);
                my $cls  = "$typ";
                if ($char eq '*') {
                    $cls = 'stop';
                } elsif ($cls eq '-') {
                    $cls = 'gap';
                }
                if ($wtSeq) {
                    $cls .= " wt" if ($i < $wtLenD && $char eq substr($wtSeq, $i, 1));
                }
                unless ($cls eq $lastCls) {
                    $row->[$j] .= "</span><span class='$cls'>";
                    $lastCls = $cls;
                }
                $row->[$j] .= $char;
            }
        }
        
        
        
        my $frame = $mut->{Frame};
        if ($insBlock) {
            # push @{$tdata}, $insBlock;
            my %tags = ("Inserted Sequence" => [$insBlock->{sequence} ]);
            $insBlock->{tags} = \%tags;
            # $args->msg_once("[!]","Insertion rows are awaiting enhanced display from Isaac","Ins blocks look WT, they're not. They are missing the 'looped out' inserted segment.","I removed the 'INS' entries since they were confusing and not displaying as intended anyway");
            # push @{$tdata}, $insBlock;
        }
        my $type  = $mut->{Type} || "Unknown";
        my $lab   = $mut->{TypeShown} || "Unknown";
        if ($type eq 'WT') {
            if ($perc) {
                $lab = "!! $lab";
            } else {
                $lab = "{Reference} $lab";
            }
        }
        my %tags  = ("Sequence Type" => [$type],
                     "Sample" => [$sample],
                     "Site" => [$site],);

        if (my $mseq = $mut->{Mut}) {
            $tags{"Mutation"} = [$mseq];
        }
        if (my $len = $mut->{CalcLen}) {
            $tags{"Len"} = [$len];
            $lab .= sprintf(" %dbp", $len);
        }
        if (my $num = $mut->{Num}) {
            $lab .= " [$num]";
            $tags{"Read Depth"} = [ $num ];
        }
        if ($perc) {
            $lab .= sprintf(" %d%%", int(0.5 + $perc));
            $tags{"Percent of Reads"} = [int(0.5 + 100 *$perc)/100];
        }

        if (0 && $str eq 'left') {
             @data = sort { $b->[0] <=> $a->[0] } @data;
        } else {
             @data = sort { $a->[0] <=> $b->[0] } @data;
        }

        # print "<pre>".join("\n", map { $seqs->{$_} } qw(dnaW prtW dna prt) )."</pre>\n";
        my $bar = {
            label    => $lab,
            name     => $lab,
            data     => \@data,
            dir      => $str,
            sequence => $seqs->{show},
            tags     => \%tags,
            alnBlk   => join("\n", map {"$_</span>"} map { @{$_} } @alnBlk),
        };
        if (defined $frame && $clas != 2) {
            my $s = $frame + 1;
            $bar->{cds} = [ $frame + 1, CORE::length($bar->{sequence}) ];
        }
        if (my $tc = $trackCol->{$type}) {
            # $track->{trackNameFontColor} = $tc;
            my $alpha = $perc ? (0.15 + 0.017 * $perc) : 1;
            $alpha = 1 if ($alpha > 1);
			$alpha = 1;	# xw disabled gradient
            $bar->{featureNameFontColor} = sprintf("rgba(%s,%0.2f)", $tc, $alpha);
        }
        # push @{$tracks}, $track;
        push @{$tdata}, $bar;
    }
    my $djs = encode_json($dataData);
    print $fh "<script>\n  new CanvasXpress('$cid'"
        . ",\n  $djs"
        . ",\n  $cjs"
        . ",\n  { mousemove: locMouseOver, click: locMouseClick }"
        . "\n );</script><br style='clear:both' />\n";
    printf($fh "<span style=''>Rejected %d class%s with < %s%% representation.</span><br />\n", $rejects, $rejects == 1 ? '' : 'es', $minPerc) if ($minPerc);
}

# xw added in order to avoid Bioperl
sub translate {
    my $dnaSeq = shift;
    $dnaSeq = uc($dnaSeq);
    my %ct = (
        TTT=>'F', TTC=>'F', TTA=>'L', TTG=>'L',
        TCT=>'S', TCC=>'S', TCA=>'S', TCG=>'S',
        TAT=>'Y', TAC=>'Y', TAA=>'*', TAG=>'*',
        TGT=>'C', TGC=>'C', TGA=>'*', TGG=>'W',
        
        CTT=>'L', CTC=>'L', CTA=>'L', CTG=>'L',
        CCT=>'P', CCC=>'P', CCA=>'P', CCG=>'P',
        CAT=>'H', CAC=>'H', CAA=>'Q', CAG=>'Q',
        CGT=>'R', CGC=>'R', CGA=>'R', CGG=>'R',

        ATT=>'I', ATC=>'I', ATA=>'I', ATG=>'M',
        ACT=>'T', ACC=>'T', ACA=>'T', ACG=>'T',
        AAT=>'N', AAC=>'N', AAA=>'K', AAG=>'K',
        AGT=>'S', AGC=>'S', AGA=>'R', AGG=>'R',

        GTT=>'V', GTC=>'V', GTA=>'V', GTG=>'V',
        GCT=>'A', GCC=>'A', GCA=>'A', GCG=>'A',
        GAT=>'D', GAC=>'D', GAA=>'E', GAG=>'E',
        GGT=>'G', GGC=>'G', GGA=>'G', GGG=>'G'
    );

    my $ps;
    for (my $i=0; $i<length($dnaSeq); $i +=3) {
        my $codon = substr($dnaSeq, $i, 3);
        if ( length($codon)==3 ) {
            $ps .= $ct{$codon};	
        }
    } 
    return $ps;
}

sub read_source {
    my $path = shift;
    return unless ($path);
    my $tr = BMS::TableReader->new(
        -colmap => {
            Sample          => 'Sample',
            'Cleavage Site' => 'Site',
            'Cleavage_Site' => 'Site',
            Sequence        => 'Seq',
            Strand          => 'Str',
            Location        => 'Loc',
            Type            => 'TypeShown',
            Frame           => 'Frame',
            'Indel Pos'     => 'Pos',
            'Indel Seq'     => 'Mut',
            'Indel_Pos'     => 'Pos',
            'Indel_Seq'     => 'Mut',
            'Indel_Length'  => 'MutLen',
            'AAseq'         => 'AA',
            Reads           => 'Num',
            Pct             => 'Perc',
        });
    my $format = $tr->format_from_file_name($path);
    $tr->has_header(1);
    $tr->format($format);
    $tr->input($path);
    my @need = qw(Sample Site Seq Loc);
    foreach my $sheet ($tr->each_sheet()) {
        my @missing;
        foreach my $col (@need) {
            my ($chk) = $tr->column_name_to_number( $col );
            push @missing, $col unless ($chk);
        }
        unless ($#missing == -1) {
            $args->msg("[-]", "Sheet $sheet is missing required columns:",
                join(', ', @missing));
            next;
        }
        my @head = $tr->header();
        # while (my $hash = $tr->next_clean_hash()) {
        while (my $row = $tr->next_clean_row()) {
            my %hash;
            for my $i (0..$#head) {
                $hash{ $head[$i] } = $row->[$i];
            }
            
            my ($samp, $site) = ($hash{Sample}, $hash{Site});
            next unless ($samp);
            if ($samp =~ /^total[_\s]*samples\s*:\s*(\d+)/i) {
                # This is actually a summary row
                print $fh "<table class='tab'><caption>Sample Summary</caption><tbody>\n";
                foreach my $cell (@{$row}) {
                    next unless ($cell);
                    if ($cell =~ /^(.+)\s*:\s*(\d+|\d+\.\d+)\s*$/) {
                        my ($t, $v) = ($1, $2);
                        $t =~ s/[\s_]+/ /g;
                        print $fh " <tr><th>$t</th><td>$v</td></tr>\n";
                    } else {
                        print $fh "<tr><td colspan='2'><i>Unrecognized data: '$cell'</i></td></tr>\n";
                    }
                }
                print $fh "</tbody></table>\n";
                next;
            }
            next unless ($site);
            $hash{Perc} ||= 0;
            my $type = $hash{Type} = &dealias($hash{TypeShown} || "");
            $hash{Class} = $type eq 'Guide' ? 2 : $type eq 'WT' ? 1 : 0;
            push @{$source->{$samp}{$site}}, \%hash;
        }
    }
}

sub cx_panel_settings {
    return {
        featureStaggered     => 0,
        graphType            => 'Genome',
        featureNameFontColor => 'rgb(29,34,43)',
        featureNameFontStyle   => 'bold',
        featureNameFontColor   => '#999999',
        featureNameFontSize    => 10,
        xAxisTickColor       => 'rgb(29,34,43)',
        wireColor            => 'rgba(29,34,43,0.1)',
        #autoAdjust           => 'true',
        #adjustAspectRatio    => 'true',
        sequenceFill         => '#cccccc',
        infoTimeOut          => 300 * 1000,
        margin               => 2,
        filterSkipNullKeys   => 1,
        subtracksMaxDefault         => 900,
    };
}

sub cx_callbacks {
    return {
        mousemove => "locMouseOver",
        click => "locMouseClick",
    };
}

sub HTML_START {
    my $colors = "";
    while (my ($key, $col) = each %{$trackCol}) {
        $colors .= sprintf(" .csp%s { font-weight: bold; color: rgb(%s); }\n", $key, $col);
    }
    
    return <<EOF;
<!DOCTYPE html>
<html lang='en'>
    <head>
    <style>
    .prot { color: purple; }
    .perc { color: navy; font-weight: bold; }
    .stop { color: yellow; background-color: red; }
    .shift { color: yellow; background-color: blue; }
    .frame { color: white; background-color: black; }
    .smallnote { width: 25em; color: brown; white-space: normal; }
    .pophead { font-size: 1.4em; font-weight: bold; color: #f90; }
    pre.aln { font-size: 0.8em; }
    pre.aln .wt { opacity: 0.2; }
    pre.aln .prt { color: purple; }
    $colors
    </style>
  <title>Crsipr Explorr</title>
  <meta http-equiv="X-UA-Compatible" content="chrome=1">

  <!--script type='text/javascript' src='http://canvasxpress.org/js/canvasXpress.min.js'></script-->
  <script type='text/javascript' src='Assets/canvasXpress.min.js'></script>
  <!--link type='text/css' rel='stylesheet' href='http://canvasxpress.org/css/canvasXpress.css' /-->
  <link type='text/css' rel='stylesheet' href='Assets/canvasXpress.min.css'>
  <link  href='Assets/0_MainStyles.css' type='text/css' rel='stylesheet' />
  <script src='Assets/0_MainScripts.js' type='text/javascript'></script>
  <script src='Assets/basic.js' type='text/javascript'></script>
  <script src='Assets/crispr2cx.js' type='text/javascript'></script>
 <body>
EOF

}

sub html_key {
    return <<EOF;
<h2>Label Key</h2>
<span style='color:red'>Deletion 2bp [42567] 32%</span> : The allele is a deletion of 2 base pairs, with 42,567 reads making up 32% of all reads<br />
<span style='color:purple'>Guide</span> : Shows the location of the Guide sequence, used to target the CRISPR mutations. Bases not in coding sequence will not be shown in the diagram. <br />
<span style='color:green'>{Reference} Wildtype</span> : This row is showing WildType sequence; {Reference} indicates that it was not (significantly) observed and is being shown for comparison purposes only.<br />
<span style='color:green'>!! Wildtype [52932] 98%</span> : This row is WildType; '!!' means it <b>was</b> observed, in this case 52,932 reads (98% of all reads)<br />

<h2>Sequence Key</h2>
<i>The shown sequence is a combined DNA/tranlsation for the bar being viewed. It is colored according to its alignment to the wildtype.</i>
<pre class='aln'>
<span class="dna wt">ATGGAAACCAACTTCTCCACTCCTCTGAATGAATATGAAGAAGTGTCCTA</span> DNA, grayed-out means it agrees with WildType in this part of the alignment
<span class="prt"></span><span class="prt wt">[M][E][T][N][F][S][T][P][L][N][E][Y][E][E][V][S][Y</span> Protein, grayed-out as it also matches WildType

<span class="dna wt">TTTCATTGCACTGGACCGCTG</span><span class="dna">--</span><span class="dna wt">TTTGTGTCCTGCATCCAGTCTGGGCCC</span> 2bp deletion, but otherwise agrees with WildType
<span class="prt wt">][F][I][A][L][D][R][C</span><span class="prt">--][L][C][P][A][S][S][L][G][P</span> The frameshift caused a change of amino acid sequence 

<span class="prt wt">][F][I][A][L][D][R][</span><span class="stop">*</span><span class="prt">-][f][v][s][c][i][q][s][g][p]</span> Lower-case amino acids indicate any translation after a stop.
</pre>
        
EOF
}
    
sub HTML_END {
    return <<EOF;
</body></html>
EOF

}
