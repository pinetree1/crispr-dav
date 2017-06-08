#!/usr/bin/env perl
# Assess how much agreement in the overlap region of forward and reverse reads.
use strict;
use Getopt::Long;

my $usage = "Usage: $0 targetseq_file(e.g. sample1.GENEX_CR1.tgt) 
    -o <str> result file 
    -v shows overlap disagreement result to stderr. 
    -h To show this message.
    This program calculates the extent to which overlapping 
    paired-end reads agree and disagree.
";

my %h;
GetOptions(\%h, 'o=s', 'v', 'h');
die $usage if @ARGV != 1 or $h{h};
my ($infile)= @ARGV;
 
open(my $inf, $infile) or die $!;

my (%wt, %indel); # {id}{strand}=>target seq for WT or indelstr for indel reads

my $line = <$inf>;
while (my $line=<$inf>) {
    next if $line !~ /\w/;
    my ($id, $seq, $indelstr, $str2, $strand) = split(/\t/, $line);
    if ( $indelstr ) {
        $indel{$id}{$strand} = $indelstr;
    } else {
        $wt{$id}{$strand} = $seq;
    }
}
close $inf; 

my ($wt_singles, $wt_pairs, $wt_pair_agreed, $wt_pair_agreed_pct) = 
   getStats(\%wt);

my ($mut_singles, $mut_pairs, $mut_pair_agreed, $mut_pair_agreed_pct) = 
   getStats(\%indel);

open(my $outf, ">" . ($h{o} || '-')) or die $!;
print $outf join("\t", "Type", "Singleton", "Overlap Pairs", "Pairs Agreed", "%Pair Agreed") . "\n";
print $outf join("\t", "WT", $wt_singles, $wt_pairs, $wt_pair_agreed, $wt_pair_agreed_pct) . "\n";
print $outf join("\t", "Indel", $mut_singles, $mut_pairs, $mut_pair_agreed, $mut_pair_agreed_pct) . "\n";
close $outf;

sub getStats {
	my $href = shift;
	my $singles = 0;
	my $pairs = 0;
	my $pairs_agreed = 0;

	print STDERR join("\t", "ID", "+ Strand", "- Strand") . "\n" if $h{v};
	foreach my $id ( keys %{$href} ) {
		if ( $href->{$id}->{'-'} && $href->{$id}->{'+'} ) {
			$pairs++;
			if ( $href->{$id}->{'-'} eq $href->{$id}->{'+'} ) {
				$pairs_agreed++;
			} else {
				print STDERR join("\t", $id, $href->{$id}->{'+'}, $href->{$id}->{'-'}) . "\n" if $h{v};
			} 
		} else {
			$singles++;
		}
	}	

	my $pair_agreed_pct = $pairs ? sprintf("%.2f", $pairs_agreed*100/$pairs) : "NA";

	return ($singles, $pairs, $pairs_agreed, $pair_agreed_pct);
}
