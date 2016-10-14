# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
package BMS::Utilities::Debug;
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #


=head1 BMS::Utilities::Debug

Debugging module that performs a recursive serialization of Perl
objects for the purpose of visual inspection. Similar to Data::Dumper.

This module is almost exculsive used through inheritance in another
module. It is possible to instantiate it on its own though, as:

  my $obj = BMS::Utilities::Debug->new();

Usage is simply by:

  warn $obj->branch( $somePerlObjectReference );

or if you wish to provide additional parameters:

  warn $obj->branch( -ref => $aPerlReference,
                     -skipkey => [ 'DATA', 'DBH' ], );

=head3 Example Output

In addition to showing a recursive view of the data structure, a stack
trace will be shown in a header above the object.

 print $args->branch( { color => 'blue', participants => ['Harry','Billy Joe','Melissa'], needReset => undef, index => { 'parrot' => 1, 'crow' => 2, 'hawk' => 91, __data__ => { A => 0.1, B => 0.99 }}} );

 ***************************************************************************
 Object Report
    [  222] main::foo
    [  218] main::bar
    [   56] main
 Strings truncated to 80 characters
 ***************************************************************************
 Hash with 4 keys HASH(0x1eaadc58)
  {color} => blue
  {index} => Hash with 4 keys HASH(0x1c5d36a0)
    {__data__} => Hash with 2 keys HASH(0x1eaadbb0)
      {A} => 0.1
      {B} => 0.99
    {crow} => 2
    {hawk} => 91
    {parrot} => 1
  {needReset} => -UNDEF-
  {participants} => Array with 3 elements ARRAY(0x1eaadbe0)
    [ 0] = Harry
    [ 1] = Billy Joe
    [ 2] = Melissa


=head3 Available Parameters

Each of the parameters below can be passed as an argument in the
branch( ) method, or alternatively can be set globally via a method, eg:

  $obj->skipkey( [ 'DATA', 'DBH' ] );


   -maxindent Default 15. If set then this will define a maximum
              nesting level (relative to the original object). A note
              will be shown and no further recursion will occur from
              that point. Circular recursion will NOT occur in any
              case, but having a limit prevents clutter when
              inspecting large objects.

   -maxstring Default 80. When showing scalar values (ie the leaves of
              a structure) this is the maximum number of characters
              will be printed. Any string that is truncated will
              include at the end "... ### char", where ### indicates
              the actual character length of the string.

    -maxarray The maximum number of array elements to be
              reported. Allows a sample of elements to be shown in
              order to prevent excessive output. If an array is
              truncated a note will be shown to that extent. See also
              -maxany.

     -maxhash Like maxarray, but will limit the number of hash keys
              shown. See also -maxany.

      -maxany Default 500. Will apply to both maxhash and maxarray.

     -skipkey An optional array reference of hash keys that are to be
              skipped. Any time a hash key is encountered that matches
              one listed in skipkey, instead of being recursed the key
              will be shown with a value of '** SKIPPED **'. Useful to
              prevent recursion into large structures that are not of
              interest, or to prevent recursing upward into
              hierarchies (eg parsed XML data) via parent reference
              keys.

    -quietkey Same as -skipkey, except the presence of the keys will
              not even be shown (ie no '** SKIPPED **').

      -nonull If false (default) then null values will be shown as
              "-UNDEF-". If true, then they will be skipped.

      -format If set to HTML, then < and > will be escaped to
              character entities.

    -noheader If you would rather not have the header / stack trace
              shown, you can set this to true

 -simplearray Default undef. If a number is passed, then any array
              that has that number of elements or fewer will be shown
              on one line as a comma separated array, eg:

              [1, bar, 'with space', -undef-] 

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

use strict;
use BMS::Utilities;

use vars qw(@ISA);
@ISA   = qw(BMS::Utilities);

our $sharedSettings = {
    max_indent => 15,
    pad_size   => 2,
    max_string => 80,
    max_any    => 500,
    format     => $ENV{HTTP_HOST} ? 'html' : 'text',
};

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {
        params => {},
    };
    bless ($self, $class);
    my $args = $self->parseparams( @_ );
    $self->max_indent( $args->{MAX_INDENT} || $args->{MAXINDENT} );
    $self->max_hash( $args->{MAXANY}  || $args->{MAX_ANY} ||
                     $args->{MAXHASH} || $args->{MAX_HASH});
    $self->max_array( $args->{MAXANY}  || $args->{MAX_ANY} ||
                      $args->{MAXARRAY} || $args->{MAX_ARRAY});
    $self->skip_key( $args->{SKIPKEY} || $args->{SKIP_KEY} );
    $self->quiet_key( $args->{QUIETKEY} || $args->{QUIET_KEY} ||
                      $args->{SKIPQUIET} || $args->{SKIP_QUIET} );
    $self->format( $args->{FORMAT} );
    return $self;
}

sub param {
    my $self = shift;
    my ($param, $val, $global) = @_;
    return undef unless ($param);
    $param = lc($param);
    if (defined $val) {
        $self->{params}{$param}   = $val;
        $sharedSettings->{$param} = $val if ($global);
    }
    return $self->{params}{$param} || $sharedSettings->{$param};
}

sub extend_param {
    my $self = shift;
    my ($param, $val, $global) = @_;
    return undef unless ($param);
    my $rv = $self->param($param, undef, $global);
    return $rv unless ($val);
    if ($rv) {
        my $rO = ref($rv);
        my $rN = ref($val);
        if ($rO && $rN && $rO eq $rN && $rO eq 'ARRAY') {
            push @{$rv}, @{$val};
            $self->param($param, $rv, $global);
        }
    } else {
        $rv = $self->param($param, $val, $global);
    }
    return $rv;
}

sub max_indent { return shift->param('max_indent', @_ ); }
sub max_string { return shift->param('max_string', @_ ); }
sub max_hash   { return shift->param('max_hash', @_ ); }
sub max_array  { return shift->param('max_array', @_ ); }
sub max_any    { return shift->param('max_any', @_ ); }
sub skip_tag   { return shift->param('skip_key', @_ ); }
sub skip_key   { return shift->param('skip_key', @_ ); }
sub quiet_key  { return shift->param('quiet_key', @_ ); }
sub no_null    { return shift->param('no_null', @_ ); }
sub no_header  { return shift->param('no_header', @_ ); }
sub format     { return shift->param('format', @_ ); }
sub fh         { return shift->param('fh', @_ ); }
sub simple_array { return shift->param('simple_array', @_ ); }

*skipkey   = \&skip_key;
*quietkey  = \&quiet_key;
*maxany    = \&max_any;
*maxarray  = \&max_array;
*maxhash   = \&max_hash;
*noheader  = \&no_header;

sub branch {
    my $self = shift;
    # If a single argument passed, it is a reference.
    unshift @_, "-ref" if ($#_ == 0);
    my $args = $self->parseparams( -indent => 0,
				   -token  => "",
				   -nohead => 0,
				   @_);

    my $text      = "";
    my $isFirst   = 0;
    my $stDat     = $self->{START};
    unless ($stDat) {
        my $memDmp = $args->{MEMDUMP};
        $stDat = $self->{START} = {
            OBSERVED => {},
            FH       => $args->{FH} || $args->{FILEHANDLE} || $self->fh(),
            FMT      => $args->{FORMAT} || $self->format(),
            MAXIND   => $args->{MAXINDENT} || $self->max_indent(),
            MAXSTR   => $args->{MAXSTRING} || $self->max_string(),
            MAXHASH  => $args->{MAXHASH}   || $args->{MAXANY} || 
                $self->max_hash() || $self->max_any(),
            MAXARR   => $args->{MAXARRAY}  || $args->{MAXANY} || 
                $self->max_array() || $self->max_any(),
            NONULL   => $args->{NONULL} || $self->no_null(),
            SEEN     => {},
            SKIPKEY  => &_list_to_hash($args->{SKIPKEY} || $args->{SKIP} ||
                                       $self->skip_key()),
            QUIETKEY => &_list_to_hash($args->{QUIETKEY} ||$self->quiet_key()),
            SIMPLEARR => $args->{SIMPLEARRAY} || $self->simple_array(),
            LENKEY   => $self->param('lenkey') || {},
        };
        # warn "SKIP: ".join(',', keys %{$stDat->{SKIPKEY}});
        if (my $memDump = $args->{MEMDUMP}) {
            $stDat->{OBJS}    = {};
            $stDat->{MAXHASH} = 0;
            $stDat->{MAXARR}  = 0;
            $stDat->{MEMDUMP} = $memDump;
        }
        unless ( $args->{NOHEADER} || $args->{NOHEAD} ||
                 $args->{NOSTACK} || $self->no_header()) {
            my $bar = ("*" x 75);
            $text .= "$bar\nObject Report\n";
            my @stack = $self->stack_trace();
            while ($#stack != -1 && $stack[0][1] =~ /\:\:branch$/) {
                # Remove branch() calls from the top of the stack
                shift @stack;
            }
            map { $text .= sprintf("    [%5d] %s\n", @{$_}) } @stack;
            my @quiet = sort keys %{$self->{START}{QUIETKEY}};
            $text .= "Quiet Hash Keys: ".join(" + ", @quiet)."\n"
                unless ($#quiet == -1);
            if (my $sa = $self->{START}{SIMPLEARR}) {
                $text .= "Simple representation of arrays <= $sa\n";
            }
            if (my $ms = $self->{START}{MAXSTR}) {
                $text .= "Strings truncated to $ms characters\n";
            }
            $text .= "$bar\n";
        }
        $isFirst   = 1;
    }
    my $lvl    = $args->{LVL} || 0;
    my $pad    = " " x ($self->param('pad_size') * $lvl);
    my @seeds = (defined $args->{REF} ? $args->{REF} :
                 defined $args->{OBJ} ? $args->{OBJ} :
                 defined $args->{OBJECT} ? $args->{OBJECT} : undef);

    my $memDmp = $stDat->{MEMDUMP};
    my $maxIn  = $stDat->{MAXIND};
    my $fmt    = $stDat->{FMT};
    my $maxStr = $stDat->{MAXSTR};
    my $simArr = $stDat->{SIMPLEARR};
    my $isHTML = $fmt =~ /html/i ? 1 : 0;

    for my $sn (0..$#seeds) {
        my $obj = $seeds[$sn];
        if (!defined $obj) {
            if ($stDat->{NONULL}) {
                next;
            }
            $obj = "-UNDEF-";
        }
        my $lead = $pad;
        my $maxLoc = $maxStr;
        $lead .= sprintf
            ("[Reference #%d of %d]\n$pad",
             $sn + 1, $#seeds + 1) if ($lvl == 0 && $#seeds != 0);
        my $keyname = $args->{KEY};
        if ($memDmp) {
            $lead = "";
        } elsif (defined $keyname) {
            $lead .= "{$keyname} => ";
            $maxLoc = $stDat->{LENKEY}{$keyname} if
                (defined $stDat->{LENKEY}{$keyname});
            if ($stDat->{QUIETKEY}{$keyname}) {
                next;
            } elsif ($stDat->{SKIPKEY}{$keyname}) {
                $text .= $lead . "** SKIPPED **\n";
                next;
            }
        } elsif (defined $args->{IND}) {
            $lead .= sprintf("[%2d] = ", $args->{IND});
        } elsif (my $token = $args->{TOKEN}) {
            $lead .= $token;
        }
        $text .= $lead;

        if ($maxIn && $lvl > $maxIn) {
            $text .= sprintf("Maximum depth of %d exceeded\n",
                                            $maxIn);
            next;
        }

        if (my $ref = ref($obj)) {
            my $rName = $ref =~ /HASH/ ? 'Hash' :
                $ref =~ /ARRAY/ ? 'Array' : undef;
            unless ($rName) {
                # Huh. Some objects are not taking kindly to ref()
                # Encountered with DB::Fasta, which AFAIK is a tie
                eval {
                    my @k = keys %{$obj};
                    if ($#k != -1) {
                        $rName = 'Hash';
                    }
                };
            }
            $rName ||= "$obj";
            if (my $num = $stDat->{SEEN}{$obj}++) {
                if ($memDmp) {
                    $stDat->{OBJ}{Duplicate}{$rName}++;
                } else {
                    $text .= sprintf("Incidence %d of %s\n", $num + 1, $obj);
                }
                next;
            }
            my ($prfx, @children);
            if ($rName eq 'Hash') {
                my @keys = sort keys %{$obj};
                my $kn   = $#keys + 1;
                $prfx    = sprintf("Hash with %d key%s", $kn,
                                   $kn == 1 ? '' : 's');
                if ($stDat->{MAXHASH} && $kn > $stDat->{MAXHASH}) {
                    @keys = splice(@keys, 0, $stDat->{MAXHASH});
                    $prfx .= sprintf(" (showing %d)", $#keys + 1);
                }
                $prfx    .= " $obj";
                @children = map { [-ref => $obj->{$_}, -key => $_] } @keys;
            } elsif ($rName eq 'Array') {
                my $kn   = $#{$obj};
                my $simple;
                if ($simArr && $kn <= $simArr) {
                    my $refKid = 0; map { $refKid++ if (ref($_)) } @{$obj};
                    unless ($refKid) {
                        $simple = "[".join(', ', map {
                            (!defined $_) ? '-undef-' :
                                ($_ =~ /\s/) ? "'$_'" : $_ } @{$obj})."]";
                        $simple = "" if ($maxLoc && length($obj) > $maxLoc);
                    }
                }
                $prfx    = sprintf("Array with %d element%s", $kn + 1,
                                   $kn == 0 ? '' : 's');
                if ($simple) {
                    @children = ([-ref => $simple]);
                } else {
                    if ($stDat->{MAXARR} && $kn+1 > $stDat->{MAXARR}) {
                        $kn = $stDat->{MAXARR} - 1;
                        $prfx .= sprintf(" (showing %d)", $stDat->{MAXARR});
                    }
                    @children = map { [-ref => $obj->[$_], -ind => $_] } (0..$kn);
                }
                $prfx .= " $obj";
            } else {
                $prfx = "$obj [$ref Object]";
            }
            if ($memDmp) {
                $stDat->{OBJ}{$rName}{Count}++;
                $stDat->{OBJ}{$rName}{Members} += $#children + 1;
                $stDat->{OBJ}{$rName}{KeyLen}  += length($keyname) if (defined $keyname);
            } else {
                $text .= "$prfx\n";
            }
            my $lPlus = $lvl + 1;
            map { $text .= $self->branch
                      ( -lvl => $lPlus, @{$_}) } @children;
        } else {
            # Scalar value
            if ($memDmp) {
                $stDat->{OBJ}{Scalar}{Count}++;
                $stDat->{OBJ}{Scalar}{Length} += length($obj);
                next;
            }
            if ($obj =~ /^ *$/) {
                if ($obj eq '') {
                    $obj = '-EMPTY STRING-';
                } else {
                    my $len = length($obj);
                    $obj = sprintf('-%d SPACE%s-', $len, $len == 1 ? '' : 'S');
                }
            }
            if ($maxLoc && length($obj) > $maxLoc) {
                my $sfx = sprintf(" ... %d char", length($obj));
                $obj = substr($obj, 0, $maxLoc). $sfx;
            }
            $obj =~ s/\n/\\n/g;
            $obj =~ s/\r/\\r/g;
            if ($isHTML) {
                $obj =~ s/\>/&gt;/g;
                $obj =~ s/\</&lt;/g;
            }
            $text .= "$obj\n";
        }
    }
    if ($isFirst) {
        if ($memDmp) {
            $text = "Memory Summary:\n";
            foreach my $type (sort keys %{$stDat->{OBJ}}) {
                my @info;
                foreach my $key (sort keys %{$stDat->{OBJ}{$type}}) {
                    push @info, "$key = ".$stDat->{OBJ}{$type}{$key};
                }
                $text .= sprintf(" %10s: %s\n", $type, join(', ', @info));
            }
        }
        $text = "<pre class='branch' style='color:red'>$text</pre>\n" if ($isHTML);
        delete $self->{START};
    }
    return $text;
}

sub _list_to_hash {
    my ($list) = @_;
    my %hash;
    if (defined $list) {
        my @members;
        if (my $ref = ref($list)) {
            if ($ref =~ /ARRAY/) {
                @members = @{$list};
            } elsif ($ref =~ /HASH/) {
                @members = keys %{$list};
            }
        } else {
            @members = ($list);
        }
        map { $hash{defined $_ ? $_ : ""} = 1 } @members;
    }
    return \%hash;
}


return 1;
