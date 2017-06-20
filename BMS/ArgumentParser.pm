package BMS::ArgumentParser;

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

use strict;
#use CGI;
use BMS::ErrorInterceptor;
use BMS::Utilities::Escape;
use BMS::Utilities::FileUtilities;
use vars qw(@ISA);
@ISA   = qw(BMS::ErrorInterceptor 
            BMS::Utilities::Escape
            BMS::Utilities::FileUtilities);

# We need to keep this global - if it goes out of scope, it closes
# filehandles associated with file upload boxes!
my $cgiObj;
our %allwaysArray = map { $_ => 1 } qw(PARAMFILE_ERR);

=head1

This module has some reserved arguments. They will be treated as
parameters for the module itself, rather than parameters that will be
used by the hosting code. The reserved parameters are:

      NOCGI - CGI parameter parsing should not occur
 BLANKPARAM - Neither CGI nor ARGV parameters should be parsed
  PARAMFILE - These three parameters allow additional parameters to be
  VALUEFILE   provided in one or more flat files
    VALFILE
 PARAMALIAS - specifies a hash structure of parameter aliases
              { foo => ['bar', 'bam'] }
              Would set 'bar' and 'bam' as aliases of 'foo'

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    # Any hash key on $self that is all caps represents a parameter name,
    # and the value is the parameter value. Starting from scratch I would
    # not have done it this way, but it was to allow for backwards
    # compatibility with an older incarnation of parameter management.

    # Any key where uc($key) ne $key represents module-internal data
    my $self = {
        defaultValues => {}, # Default values from new() or param file
        argumentCase  => {}, # parameter case as provided by user
        defaultOnly   => {}, # parameters that can not be changed from default
        paramAliases  => {}, # parameter aliases
        isDefault     => {}, # parameters that are still the default value
        pFiles        => {}, # list of parameter files
        notPassed     => {}, # parameters provided by a param file
        blockQuote    => {}, # params to be formatted as blocks in to_text()
    };
    # Scalar keys
    # xssProtect  - XSS protection mode
    # readErr     - Errors encountered while reading a param file
    # ignoreParam - user parameters that were ignored due to default_only()

    bless ($self, $class);
    my $defaults = $self->set_defaults( @_ );
    my $argCase  = $self->{argumentCase};

    # Prescan ARGV
    my @passed = @ARGV;
    my %argvTemp;
    while (@passed) {
        my $arg = shift @passed;
        if ($arg =~ /^\-(.+)/) {
            # Settings indicated by -blahblah
            $arg    = $1;
            my $val = shift @passed;
            $val    = 1 unless (defined $val && $val ne "");
            if ($val =~ /^\-/) {
                # Oops, shifted off another argument, put it back:
                unshift @passed, $val;
                $val = 1;
            }
            my $uckey = $self->param_alias($arg);
            # $self->msg("[ARGV]", "$uckey [$arg] = $val");
            push @{$argvTemp{$uckey}}, [$arg, $val];
        }
    }
    my @argvKeys = keys %argvTemp;
    
    # 0 = not specified, -1 = No, 1 = Yes
    my $isCGI = 0;
    if ($argvTemp{NOCGI}) {
        $isCGI = $argvTemp{NOCGI}[-1][1] ? -1 : 1;
    } elsif (defined $defaults->{NOCGI}) {
        $isCGI = $defaults->{NOCGI} ? -1 : 1;
    }
    # warn "isCGI = [$isCGI]" . $self->branch({ argv => \%argvTemp, def => $defaults});
    my $isAPI = 0;

    my %temp;
    if ($defaults->{BLANKPARAM}) {
        # An object is being created without attempting to parse
        # arguments from the environment (CGI or @ARGV)
        $isAPI = 1;
        delete $defaults->{BLANKPARAM};
    } elsif ($#argvKeys > -1 && $isCGI < 1) {
	# If any arguments have been passed, then do not bother trying
	# to read CGI values
        while (my ($ucarg, $kvs) = each %argvTemp) {
            foreach my $kv (@{$kvs}) {
                my ($arg, $val) = @{$kv};
                push @{$temp{$ucarg}}, $val;
                $argCase->{$ucarg} ||= $arg;
	    }
	}
    } elsif ($#ARGV > -1 && $#ARGV != 0 && $ARGV[0]) {
        # When ARGV is populated in a CGI environment, it means a
        # space separated list of values were passed:
        # foo.pl?abc+123+00423
        push @{$self->{ARGV_LIST}}, @ARGV;
    } elsif ($isCGI > -1) {
        $cgiObj ||= CGI->new();
	# First set key/values for the variables passed by the CGI
        my @params = $cgiObj->param;
	foreach my $var (@params) {
	    my $ucvar = $self->param_alias($var);
	    my @val   = $cgiObj->param($var);
	    if ($#val < 0) {
                # This is a parameter with no value
                push @{$temp{EMPTY_PARAMETERS}}, $var;
	    } elsif ($val[0] ne "") {
                # Use 'push' to catch multiple entries in the GET
		push @{$temp{$ucvar}}, @val;
                $argCase->{$ucvar} ||= $var;
		if (my $fh = $cgiObj->upload($var)) {
		    # This argument points to a file
		    push @{$temp{$ucvar.'_FH'}}, $fh;
		}
            }
	}
    }

    if (exists $temp{GETSTRING} && $temp{GETSTRING}[0] =~ /\=/) {
        foreach my $str (@{$temp{GETSTRING}}) {
            foreach my $pair (split(/\&/, $str)) {
                my ($key, $val) = split(/\=/, $pair);
                my $ucvar = $self->param_alias($key);
                # Unescape spaces:
                $val =~ s/\+/ /g;
                # Unescape in two steps (to avoid double action on escaped %)
                while ($val =~ /(\%([0-9a-f][0-9a-f]))/i) {
                    my $orig = $1;
                    my $rep  = 'ASCIICHAR{'.hex($2).'}';
                    $val     =~ s/\Q$orig\E/$rep/g;
                }
                while ($val =~ /(ASCIICHAR\{(\d+)\})/) {
                    my $orig = $1;
                    my $rep  = chr($2);
                    $val     =~ s/\Q$orig\E/$rep/g;
                }
                push @{$temp{$ucvar}}, $val;
                $argCase->{$ucvar} ||= $key;
            }
        }
    }

    # Parameter files are analyzed in a loop, to allow one file to
    # specify yet other ones.
    # A "Value file" will always contribute its data to the arguments
    # A "Param file" will only contribute if no other values are set
    my @pfiles;
    foreach my $pfk (qw(PARAMFILE VALUEFILE VALFILE)) {
        my @srcs  = (\%temp, $defaults);
        for my $s (0..$#srcs) {
            unless (exists $srcs[$s]->{$pfk}) {
                next;
            }
            my $pfReq = $srcs[$s]->{$pfk};
            my $isVal = $s ? $isAPI : $pfk =~ /VAL/ ? 1 : 0;
            my @reqs = ($pfReq);
            if (my $r = ref($pfReq)) {
                if ($r eq 'ARRAY') {
                    @reqs = @{$pfReq};
                } else {
                    # Stringify modules
                    my $txt = "".$pfReq;
                    if ($txt =~ /^(\S+)=(HASH|ARRAY)/) {
                        @reqs = ($1);
                    } else {
                        $self->msg("[?]", "Unusual parameter file request", $pfReq);
                        @reqs = $txt;
                    }
                }
            }
            # my @reqs  = ref($pfReq) ? @{$pfReq} : ($pfReq);
            foreach my $file (@reqs) {
                push @pfiles, [$file, $isVal];
            }
        }
    }
    while ($#pfiles != -1) {
        my $dat = shift @pfiles;
        # The return value from parse_pvfile() is a list of any new
        # parameter files found in the one being parsed
        push @pfiles, $self->parse_pvfile( @{$dat}, \%temp );
    }

    # Finally, reduce single-element arrays to scalar values, except for
    # special cases. We will also exclude any values that were trying
    # to set 'default only' parameters
    my $defOnlys = $self->{defaultOnly};
    my @protected;
    foreach my $ucvar (keys %temp) {
        my $array = $temp{$ucvar};
        if ($defOnlys->{$ucvar}) {
            push @protected, $ucvar;
        } elsif ($#{$array} == 0 && !$allwaysArray{$ucvar}) {
            # Single values pass as just the first entry
            $self->{$ucvar} = $array->[0];
        } else {
            # More than one entry, keep it as an array:
            $self->{$ucvar} = $array;
        }
    }
    $self->{ignoreParam} = \@protected unless ($#protected == -1);

    # Then set any default values that might be needed
    foreach my $var (sort keys %{$defaults}) {
        my $val = $defaults->{$var};
        if (exists $self->{$var}) {
            # $self->msg("[USER]", "$var = $val");
            # There is already a value set for this variable
            # Do nothing at all if the default differs from the set value:
            if (defined $val) {
                next if ($self->{$var} ne $val);
            } elsif (defined $self->{$var}) {
                next;
            }
            # If the default equals the user-supplied value, go ahead
            # and execute below to capture the fact that it is still a 
            # default value, and to capture the case of the argument name
        }
        # $self->msg("[SET DEFAULT]", "$var = $val");
        $self->set_param( $var, $val );
        $self->flag_as_default( $var );
    }
    return $self;
}

*setval    = \&set_param;
*setvalue  = \&set_param;
*setparam  = \&set_param;
*set_val   = \&set_param;
*set_value = \&set_param;
sub set_param {
    my $self = shift;
    if (my $var = shift) {
        $var =~ s/^\-//;
        my $ucvar = $self->param_alias($var);
        $self->{ $ucvar } = shift;
        $self->{argumentCase}{ $ucvar } ||= $var;
        return $self->val($var);
    }
    return undef;
}

sub param_alias {
    my $self = shift;
    my $req  = shift;
    $req =~ s/^\-// if ($req);
    return undef if (!defined $req || $req eq '');
    my $rv = $req = uc($req);
    my $alis = $self->{paramAliases};
    if ($#_ == -1) {
        # return the alias for this key, if it exists
        $rv = $alis->{$req} if (defined $alis->{$req});
    } else {
        # Set an alias for the key
        foreach my $ali (@_) {
            $ali =~ s/^\-// if ($ali);
            if (defined $ali && $ali ne "") {
                my $ucali = uc($ali);
                $alis->{$ucali} = $req;
            }
        }
    }
    return $rv;
}

sub set_if_false {
    my $self = shift;
    my ($var, $nv) = @_;
    $self->set_param($var, $nv) unless ($self->val($var));
    return $self->val($var);
}


*set_if_undefined = \&set_if_undef;
*set_if_null      = \&set_if_undef;
sub set_if_undef {
    my $self = shift;
    my ($var, $nv) = @_;
    $self->set_param($var, $nv) unless (defined $self->val($var));
    return $self->val($var);
}


*remove_param = \&clear_param;
*delete_param = \&clear_param;
*remove_val   = \&clear_param;
*delete_val   = \&clear_param;
*clear_val    = \&clear_param;
sub clear_param {
    my $self = shift;
    my $rv;
    if (my $var = shift) {
        $var =~ s/^\-//;
        my $ucvar = $self->param_alias($var);
        $rv = $self->{ $ucvar };
        delete $self->{ $ucvar };
    }
    return $rv;
}

sub flag_as_default {
    my $self = shift;
    if (my $var = shift) {
        $var =~ s/^\-//;
        $self->{isDefault}{$self->param_alias($var)} = 1;
    }
}

sub is_default {
    my $self = shift;
    my $var  = shift;
    return -1 unless (defined $var);
    $var =~ s/^\-//;
    return $self->{isDefault}{$self->param_alias($var)} ? 1 : 0;
}

sub set_defaults {
    my $self = shift;
    my $passed   = $self->parseparams( @_ );
    my $defaults = $self->{defaultValues} ||= {};
    foreach my $key (sort keys %{$passed}) {
        my $val = $passed->{$key};
        $defaults->{$key} = $val;
        # $self->msg("[GET DEFAULT]", "$key = $val");
    }
    if (my $aliHash = $defaults->{PARAMALIAS}) {
        delete $defaults->{PARAMALIAS};
        while (my ($main, $alis) = each %{$aliHash}) {
            # Set the aliases
            my $mkey = $self->param_alias( $main, @{$alis});
            # $self->msg("[ALIAS]", "$mkey ($main) <- ".join(',', @{$alis}));
            # We also now collect any values under the main and alias
            # parameters under the single main parameter
            my @allKeys = ($mkey, map {uc($_)} @{$alis});
            my @vals;
            for my $i (0.. $#allKeys) {
                my $uckey = $allKeys[$i];
                if (exists $defaults->{$uckey} &&
                    defined $defaults->{$uckey}) {
                    my $v = $defaults->{$uckey};
                    my $r = ref($v) || "";
                    push @vals, $r eq 'ARRAY' ? @{$v} : ($v);
                    delete $defaults->{$uckey};
                }
            }
            if ($#vals != -1) {
                $defaults->{$mkey} = ($#vals == 0) ? $vals[0] : \@vals;
            }
        }
    }
    return $defaults;
}

# http://en.wikipedia.org/wiki/ANSI_escape_code
# 30+ = color, 40+ = background
#0 	1 	2 	3 	4 	5 	6 	7
#Black 	Red 	Green 	Yellow 	Blue 	Magenta	Cyan 	White
our $shellPreCol = "\033["; #1;33m
our $shellProCol = "\033[0;49m";
our $shellTermCols = {
    'Time'        => ['37',   'TimeStamp'],
    'v'           => ['1;32;92', 'DoneContig'],
    'x'           => ['37',   'ClearMsg'],
    '*'           => ['32',   'GenericMsg'],
    'DB'          => ['35',   'DBMsg'],
    '#'           => ['36',   ''],
    '^'           => ['34',   ''],
    'OUT'         => ['36;1', ''],
    'FILE'        => ['36;1', ''],
    'INPUT'       => ['36;1', ''],

    'Info'        => ['35',   'InfoMsg'],
    'Tip'         => ['35',   'InfoMsg'],
    'NOTE'        => ['35',   'NoteMsg'],

    '!'           => ['31;7', 'StrongErrorMsg'],
    'Err'         => ['31',   'ErrorMsg'],
    'ERROR'       => ['31;7', 'StrongErrorMsg'],
    '?'           => ['33;7', 'WarnMsg'],
    'WARN'        => ['33;7', 'WarnMsg'],
    'ALERT'       => ['33;7', 'WarnMsg'],
    'W'           => ['33;7', 'WarnMsg'],

    'REJECT'      => ['30;7', 'RejectedSeq'],
    'Edit'        => ['37;7', 'EditSeq'],

    'Project'     => ['35;7', 'GotProject'],
    'Requisition' => ['34;7', 'GotRequisition'],
    'Sample'      => ['36;7', 'GotSample'],
    'Contig'      => ['7',    'GotContig'],

    '+'           => ['37',   ''],
    '-'           => ['33',   ''],
    'CheckMe'     => ['30',   ''],
    'Alter'       => ['', 'AlterMsg'],
    'Purge'       => ['', 'PurgeMsg'],
    'SeqChange'   => ['', 'SeqChange'],
    'DEBUG'       => ['35;47', 'DebugMsg'],
    'BENCH'       => ['36;', 'DebugMsg'],
    'DUMP'        => ['', 'DumpMsg', 'pre'],
    'SQL'         => ['37', 'DumpMsg', 'pre'],
    '-FC-'        => ['34', ''],
    'LH'          => ['36', ''],
    '!!'          => ['31;7', ''],
    '!'           => ['33;7', ''],
    '>'           => ['33;46', 'OutputMsg'],
    '<'           => ['36;43', 'InputMsg'],
    '.'           => ['32;2', ''],
    ''            => ['', ''],
    ''            => ['', ''],
};

*shell_colors = \&shell_coloring;
sub shell_coloring {
    my $self = shift;
    $self->intercept_errors();
    $self->manage_callback('FormatCallback', sub {
        my $self = shift;
        my $txt  = shift;
        return "" unless (defined $txt);
        if ($txt =~ /^\s*\[([^\]]+)\]/) {
            my $tok = $1;
            $tok = '-FC-' if ($tok =~ /^\s*\d+$/);
            my $tca = $shellTermCols->{$tok};
            if ($tca && $tca->[0]) {
                my $nl = "";
                if ($txt =~ /^(.+)([\n\r]+)$/s) {
                    # Want the last newline(s) AFTER reverting back to normal:
                    ($txt, $nl) = ($1, $2);
                }
                $txt = sprintf("%s%sm%s%s%s", $shellPreCol, 
                               $tca->[0], $txt, $shellProCol, $nl);
            }
        }
        return $txt;
    }, 'isGlobal');
    
}

sub set_mime {
    my $self = shift;
    my $args = $self->parseparams( -mime => 'html',
                                   @_ );
    my $mime  = $args->{MIME} || 'html';
    my $cdUrl = $args->{CODEURL};
    $mime = "text/$mime" unless ($mime =~ /\//);
    if (my $file = $args->{MIMEFILE}) {
        # Should be escaped, but I am not sure how at the moment
        printf("Content-Disposition: attachment; filename=%s;\n",
               $file);
    }
    unless ($args->{NOPRINT}) {
        $mime .= "; charset=utf-8"
            if ($mime =~ /html/ && $mime !~ /charset/);
        # print "Parrot: sqwaaauuuk\n";
        # print "Cache-Control: max-age=600\n";
        print "Content-type: $mime\n\n";
    }
    if (my $em = $args->{MAIL} || $args->{ERRMAIL} ||
        $self->val(qw(errormail errmail))) {
        $self->error_mail($em);
    }
    return unless (($ENV{HTTP_HOST} && !$args->{NOREDIRECT}) || 
                   $args->{REDIRECT});

    $self->intercept_errors();
    my $closure = $self;
    my $sanitize = "";

    $self->message_output('stdout');
    if (my $maskPath = $args->{ERRORDIR} || $args->{SANITIZE}) {
        # Security does not want us showing stack traces to the user
        # They also do not want us sending stack traces in email
        # So this option allows the stack to be written to a
        # restricted-access file location, which can be only viewed
        # by the development team.
       $maskPath =~ s/\/$//;
        my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
        $sanitize = sprintf("%s/%d/%02d/%02d/%02d.%02d.%02d-%d.html", 
                            $maskPath, $year + 1900, $mon+ 1, $mday,
                            $hour, $min, $sec, $$);
        my $errCB = $self->err_callback();
        my $newCB = $self->err_callback(sub {
            my ($obj, $lines) = @_;
            # print "<pre>".$closure->stack_trace()."</pre>";
            # First write the full error to the (presumably secure)
            # file:
            my $detailMsg;
            $closure->assure_dir($sanitize, 'isFile');
            if (open(SANFILE,">>$sanitize")) {
                my $isReady = $closure->{storedEnv}++;
                unless ($isReady) {
                    my $prog = $0;
                    print SANFILE "<html><title>Error report for $prog</title><head><style> .tab { border-collapse: collapse; } .tab th { background-color: #ffc; } .tab th, .tab td { overflow: scroll; empty-cells: show; vertical-align: top; border: #fc9 solid 1px; padding: 2px; } td i { color: cyan; }</style></head><body>\n";
                    my $indFile = sprintf("%s/%d/%02d/%02d/index.html", 
                                          $maskPath, $year + 1900, $mon+ 1, $mday);
                    if (open(IND, ">>$indFile")) {
                        my $short = $sanitize;
                        $short =~ s/.+\///;
                        print IND sprintf
                            ("<b>%02d:%02d:%02d %s</b> <a href='%s'>%s</a>",
                             $hour, $min, $sec, $ENV{LDAP_USER} || "User",
                             $short, $0);
                        print IND "<br />\n";
                        close IND;
                    }
                }
                # print SANFILE "<pre>";
                $self->message_output( *SANFILE );
                &{$errCB}( $obj, $lines );
                # print SANFILE "<pre>\n";
                unless ($isReady) {
                    # Add the environment and parameters
                    my $pfile = $sanitize;
                    $pfile    =~ s/html$/param/;
                    $pfile   .= '.param' unless ($pfile =~ /\.param$/);
                    if (open(PFILE, ">$pfile")) {
                        print PFILE $closure->to_text();
                        close PFILE;
                        my $pShort = $pfile;
                        $pShort    =~ s/.+\///;
                        print SANFILE "<a href='$pShort'>Parameter File</a><br />\n";
                    }
                    print SANFILE "<table class='tab'><caption>Environment:</caption><tbody><tr><th>ENV</th><th>Value</th></tr>\n";
                    foreach my $var (sort keys %ENV) {
                        next if ($var eq 'HTTP_COOKIE');
                        my $val = !defined $ENV{$var} ? "<i>UNDEF</i>" : $ENV{$var} eq '' ? "<i>Empty String</i>" : $ENV{$var};
                        $val = join("<br />", split(/:/, $val))
                            if ($var eq 'PATH');
                        print SANFILE "<tr><th>$var</th><td>$val</td></tr>\n";
                    }
                    print SANFILE "</tbody></table>\n";
                }
                close SANFILE;
                $detailMsg = $closure->path2link($sanitize, { 
                    style => 'color:gray ! important; font-size:0.6em;',
                    target => '_blank' }, "TechReport");
            } else {
                $detailMsg = "<span style='font-style:italic; color:gray;'>Failed to create TechReport at $sanitize</span>";
            }
            $self->message_output('stdout' );
            &{$errCB}( $obj, [ 'NO_STACK', @{$lines}, $detailMsg ] );
            
        }, 'isGlobal');
        $self->manage_callback('DeathCallback', $newCB, 'isGlobal');
        # print "<pre>$sanitize\n $errCB -> $newCB</pre>";
    }
    
    my $fmtCB = sub {
        my $self = shift;
        my $txt  = shift;
        return "" unless (defined $txt);
        return "" if ($closure->{errorLoop}++);
        my $style = "";
        my $tok   = "";
        if ($txt =~ /^\[([^\]]+)\]/) {
            $tok = $1;
        }
        if ($txt =~ /FATAL ERROR/) {
            $style = "color: red; background-color: yellow";
        } elsif ($tok =~ /^(WARN|ERR|\!+)/) {
            $style = "color: red";
        } elsif ($tok =~ /^(ALERT|CAUTION)/) {
            $style = "color: #f93;"
        } elsif ($tok) {
            $txt =~ s/^\s*\[[^\]]+\]\s+//;
            my $stc = $shellTermCols->{$tok};
            my $cls = $stc && $stc->[1] ? " class='$stc->[1]'" : "";
            my $lead = ($tok eq '*') ? '' : "<span style='font-weight:bold; color: green; background-color:yellow;'>".$closure->esc_xml($tok)."</span> ";
            my $tag = $stc->[2] || "";
            my @lines = split(/\s*[\n\r]+\s*/, $txt);
            @lines = ("<pre>$txt</pre>") if ($tag eq 'pre');
            $closure->{errorLoop} = 0;
            return "<ul style='color: navy'>\n  <li$cls>$lead".
                join("<br />\n  ", @lines)."</li>\n</ul>\n";
        }
        my (%params, @showBits);
        foreach my $line (split(/[\n\r]/, $txt)) {
            if ($line =~ /^(.*)FormatParam\s+(\S+)=(.+)/) {
                $params{$2} = $3;
                $line = $1;
                next unless ($line);
            }
            my ($ln, $mod);
            if ($line =~ /^\s*\[\s*(\d+)\] (\S+?)(\:\:[^\:]+)?\s*$/) {
                ($ln, $mod) = ($1, $2);
            } elsif ($line =~ /STACK:\s+(.+)\s*$/) {
                # BioPerl
                my $bit = $1;
                if ($bit =~ /(\S+) \S+:(\d+)\s*$/) {
                    ($ln, $mod) = ($2, $1);
                    $mod =~ s/::[^:]+$//;
                } else {
                    next;
                }
            }
            if ($ln) {
                # Security wants stack traces gone from email
                next if ($sanitize && $params{Mail});
                if ($cdUrl) {
                    # Hyperlink the stack to code repository
                    my $url = $cdUrl;
                    $mod = $0 if ($mod eq 'main');
                    $url =~ s/_MODULE_/$mod/g;
                    $url =~ s/_LINE_/$ln/g;
                    my $link = "<a href='$url' target='code'>$ln</a>";
                    $line =~ s/$ln/$link/;
                }
            } elsif ($line =~ /(.+) at \S+ line \d+\.\s*$/) {
                # Error line number
                $line = $1 if ($sanitize);
            }
            # Generic message
            push @showBits, $line;
        }
        if ($sanitize && $params{Report}) {
            push @showBits, $closure->path2link($sanitize, { 
                style => 'color:gray ! important; font-size:0.6em;',
                target => '_blank' }, "TechReport");
        }

        $style = " style='$style'" if ($style);
        $closure->{errorLoop} = 0;
        return "<pre$style>".join("\n", @showBits)."</pre>\n";
    };
    $self->manage_callback('FormatCallback', $fmtCB, 'isGlobal');
}

sub parse_pvfile {
    my $self = shift;
    my ($req, $isValue, $target) = @_;
    my @list = ref($req) ? @{$req} : ($req);
    $target ||= $self;
    my @newPfiles;
    my $defaults = $self->{defaultValues} || {};
    my $argCase  = $self->{argumentCase}  || {};
    foreach my $pfile (@list) {
        next unless ($pfile);
        next if ($self->{pFiles}{$pfile}++);
        $pfile = $self->module_path( -module => $pfile, -suffix => 'param', )
            if ($pfile =~ /\:\:/ && ! -e $pfile);
        my ($pp, $ac) = $self->parse_paramfile( $pfile );
        if (my $err = $self->{readErr}) {
            push @{$defaults->{PARAMFILE_ERR}}, $err;
        }
        if (my $pf = $pp->{PARAMFILE}) {
            push @newPfiles, map { [$_, 0] } ref($pf) ? @{$pf} : ($pf);
            # delete $pp->{PARAMFILE};
        }
        if (my $vf = $pp->{VALUEFILE}) {
            push @newPfiles, map { [$_, 1] } ref($vf) ? @{$vf} : ($vf);
            # delete $pp->{VALUEFILE};
        }
        my $locIV  = $isValue || $pp->{PARAMOVERWRITE};

        # -clearparameter indicates that the values in this file should
        # overwrite any already set:
        map { $target->{$_} = [] } keys %{$pp} if
            ($pp->{CLEARPARAMETER} || $pp->{CLEARPARAM});
        my %seenVar;
        while (my ($var, $val) = each %{$pp}) {
            if ($locIV) {
                # These values should be added to any already set

                # ADDED 23 Sep 2010:
                # The first time we see a variable in this file, make a note
                # if it has been used previously. This is to prevent multiple
                # value files from turning a scalar value into an array by
                # stuffing the same value in several times

                $seenVar{$var} ||= { map { $_ => 1 } @{$target->{$var} || []}};

                # Not adding a previously added value MIGHT CAUSE PROBLEMS:
                push @{$target->{$var}}, $val unless ($seenVar{$var}{$val});
            } else {
                # The parameter file represents a defaults file
                $defaults->{$var} = $val;
                $self->{notPassed}{$var} = 1;
            }
        }
        while (my ($ucarg, $arg) = each %{$ac}) {
            $argCase->{$ucarg} ||= $arg;
        }
    }
    return @newPfiles;
}

sub parse_paramfile {
    my $self = shift;
    my $pfile = shift;
    my (%pp, %argCase);
    return wantarray ? (\%pp,\%argCase) : \%pp unless ($pfile);

    $self->{readErr} = "";
    if ($pfile !~ /\.param$/) {
        $self->{readErr} = "Security failure: Parameter file '$pfile' does not end with .param";
    } elsif (open(PFILE,"<$pfile")) {
        my ($var, $val, $bqt, %variables) = ("", "");
        while (<PFILE>) {
            s/[\n\r]+$//;
            # $self->msg("[LINE]",$_);
            if ($bqt) {
                if ($_ eq $bqt) {
                    # End of block quote
                } else {
                    # Extend the block, include a newline
                    $val .= $_ . "\\n";
                    next;
                }
            } elsif (/^\s*(\$[A-Z0-9_]+)\s*\=\s*(.+)$/) {
                # Variable token
                # $FOO = hello world
                $variables{$1} = $2;
                next;
            } elsif (/^\s*\-?(\S+)\s+\=\>?\s+(.*?)\s*$/) {
                $var = $self->param_alias($1);
                $val = $2;
                $argCase{$var} ||= $1;
                if ($val =~ /^\<\<(\S+)\;\s*$/) {
                    # block quote token start
                    $bqt = $1;
                    $val = "";
                    next;
                }
            } elsif ($var) {
                $val .= $_;
            }
            if ($var) {
                if ($val =~ /\\$/ && !$bqt) {
                    # Trailing slash used for line continuation
                    $val =~ s/\\$//;
                    next;
                }
                # Store the value in the variable
                # Map escaped newlines and tabs
                $val =~ s/\\n/\n/g;
                $val =~ s/\\t/\t/g;
                # Swap out variables for their values:
                while (my ($in, $out) = each %variables) {
                    $val =~ s/\Q$in\E/$out/g;
                }
                if ($bqt) {
                    # Remove last terminal newline
                    $val =~ s/\n$//;
                    $bqt = "";
                }
                if ($val =~ /^ARRAY\[([^\]]+)\]\[([^\]]+)\]/) {
                    # Array designation
                    # NEED A MECHANISM TO ESCAPE QUOTES
                    my ($qt, $arrtxt) = ($1, $2);
                    my $max = (length($arrtxt) || 1)/2;
                    my @stack;
                    my $iloop = 0;
                    while ($arrtxt =~ /(\Q$qt\E([^\Q$qt\E]+)\Q$qt\E)/) {
                        my ($rep, $val) = ($1, $2);
                        push @stack, $val;
                        my $nv = "STACK".$#stack;
                        $arrtxt =~ s/\Q$rep\E/$nv/g;
                        if (++$iloop > $max) {
                            $self->err("Potential infinite loop parsing array string", $arrtxt);
                            last;
                        }
                    }
                    # warn $arrtxt;
                    foreach my $bit (split(/\,/, $arrtxt)) {
                        if ($bit =~ /^STACK(\d+)$/) {
                            push @{$pp{$var}}, $stack[$1];
                        } else {
                            $self->err("Unrecognized array token '$bit'");
                        }
                    }
                } else {
                    push @{$pp{$var}}, $val;
                }
            }
            $val = "";
            $var = "";
        }
        close PFILE;
        while (my ($var, $val) = each %pp) {
            $pp{$var} = $val->[0] if ($#{$val} == 0 && !$allwaysArray{$var});
        }
    } else {
        $self->{readErr} = "Failed to read parameter file '$pfile': $!";
    }
    return wantarray ? (\%pp,\%argCase) : \%pp;
}

sub xss_protect {
    my $self = shift;
    if (defined $_[0]) {
        my $nv = lc($_[0]);
        if ($nv =~ /\|/) {
            # Vertical pipe presumed to separate whitelisted tags
            my @ok;
            foreach my $tag (split(/\s*\|\s*/, $nv)) {
                push @ok, $tag if ($tag && $tag =~ /^[a-z]$/);
            }
            $nv = $#ok == -1 ? 1 : \@ok;
        }
        $self->{xssProtect} = $nv;
    }
    return $self->{xssProtect};
}

sub file_path_protect {
    my $self = shift;
    my $key  = $self->param_alias(shift);
    if (my $pattern = shift) {
        $self->{pathKeys}{$key}{$pattern} = 1;
    }
    return $self->{pathKeys}{$key};
}

sub default_only {
    my $self = shift;
    # Allow some keys to be specified as only recovering values from default
    # settings. This prevents user over-ride of the values
    # The idea is to provide some protection from URL hacking of sensitive
    # values (paths, URLs, etc)
    foreach my $key (@_) {
        next unless ($key);
        $self->{defaultOnly}{$self->param_alias($key)} = 1;
    }
    return $self->{defaultOnly} || {};
}

*value = \&val;
sub val {
    my $self = shift;
    my $rv   = $self->rawval(@_);
    return $rv unless (defined $rv);
    foreach my $key (@_) {
        if (my $fp = $self->file_path_protect( $key )) {
            foreach my $re (keys %{$fp}) {
                if ($rv =~ /$re/) {
                    $self->msg_once
                        ("[!!]","Illegal filepath provided for '".
                         $self->esc_xml($key)."'", $self->esc_xml($rv),
                         "File system security violation!");
                    # $self->err("stack trace");
                    return undef;
                }
            }
        }
    }
    # warn join(" = ", $_[0], $self->param_alias($_[0]), $rv);
    my $xss  = $self->xss_protect();
    return $rv unless ($xss);
    # Non-null value, and XSS protection has been requested
    my @vals;
    my $rr = ref($rv) || "";
    my $mod = ref($xss) ? sub {
        # A whitelist of allowed tags is passed
        my $txt = shift;
        return $txt if (!defined $txt || ref($txt));
        my $pos = 0;
        my $chk = '(<\/?('.join('|', @{$xss}).')>)';
        while (1) {
            my $ltPos = index($txt, '<', $pos);
            my $gtPos = index($txt, '>', $pos);
            if ($gtPos != -1 && ($ltPos == -1 || $ltPos > $gtPos)) {
                # Next character is a right bracket
                $pos = $gtPos;
                substr($txt, $pos, 1) = '&gt;';
                next;
            }
            if ($ltPos != -1) {
                # An opening left bracket
                $pos = $ltPos;
                if (substr($txt, $pos) =~ /^$chk/i) {
                    # Looks ok - leave as is
                    $pos += length($1);
                } else {
                    substr($txt, $pos, 1) = '&lt;';
                }
                next;
            }
            # No more brackets
            last;
        }
        return $txt;
    } : $xss =~ /all/ ? sub {
        # Aggressive - will escape all instances of < or >
        my $txt = shift;
        return $txt if (!defined $txt || ref($txt));
        $txt =~ s/</&lt;/g;
        $txt =~ s/>/&gt;/g;
        return $txt;
    } : sub {
        # This is conservative, in that it only will replace tags
        # that are paired
        my $txt = shift;
        return $txt if (!defined $txt || ref($txt));
        $txt =~ s/<([^>]+)>/&lt;$1&gt;/g;
        return $txt;
    };
    if (!$rr) {
        return &{$mod}( $rv );
    } elsif ($rr eq 'ARRAY') {
        my @rve;
        foreach my $v (@{$rv}) {
            push @rve, &{$mod}($v);
        }
        return \@rve;
    } elsif ($rr eq 'HASH') {
        my %rve;
        while (my ($k, $v) = each %{$rv}) {
            $rve{ &{$mod}($k) } = &{$mod}($v);
        }
        return \%rve;
    } else {
        return $rv;
    }
}

# Bypasses XSS protection
*rawvalue = \&rawval;
sub rawval {
    my $self = shift;
    my $defO = $self->default_only();
    my $defs = $self->{defaultValues} || {};
    foreach my $key (@_) {
        next unless (defined $key);
        my $uckey = $self->param_alias($key);
        my $src   = $defO->{$uckey} ? $defs : $self;
        if (exists $src->{$uckey} && defined $src->{$uckey}) {
            return $src->{$uckey};
        }
    }
    return undef;
}

# For use in HTML forms
sub formval {
    my $self = shift;
    my $val  = $self->rawval(@_);
    return "" if (!defined $val);
    return $self->esc_xml( $val );
}

sub each_split_val {
    my $self = shift;
    my @rv;
    my $splitter = '\s*[\n\r]+\s*';
    if ($_[0] && $_[0] =~ /^\/(.+)\/$/) {
        $splitter = $1;
        shift @_;
    }
    foreach my $param (@_) {
        my $v = $self->val($param);
        next unless (defined $v);
        my @vals = ($v);
        if (my $r = ref($v)) {
            if ($r eq 'ARRAY') {
                @vals = @{$v};
            }
        }
        foreach my $vl (@vals) {
            if (ref($vl)) {
                push @rv, $vl;
            } else {
                push @rv, split($splitter, $vl);
            }
        }
    }
    # warn "$splitter = ".(join('+',@rv) || "--");
    return @rv;
}

sub single_val {
    my $self = shift;
    my $val  = $self->val(@_);
    return $val if (!defined $val);
    my $ref = ref($val);
    return $val unless ($ref && $ref eq 'ARRAY');
    foreach my $v (@{$val}) {
        return $v if (defined $v && $v ne '');
    }
    return $val->[0];
}

sub module_parameters {
    my $self = shift;
    my $path = $self->module_path( -module => shift,
                                   -suffix => 'param', );
    my $args = {};
    if ($path && -s $path) {
        $args = $self->parse_paramfile( $path );
    }
    return wantarray ? %{$args} : $args;
}

sub file_parameters {
    my $self = shift;
    my $src  = shift;
    my @try  = ("$src.param");
    if ($src =~ /(.+)\.[^\.]{1,6}$/) {
        push @try, "$1.param";
    }
    my $args = {};
    foreach my $path (@try) {
        if ($path && -s $path) {
            $args = $self->parse_paramfile( $path );
            last;
        }
    }
    return wantarray ? %{$args} : $args;
}

*each_key   = \&all_keys;
*each_param = \&all_keys;
sub all_keys {
    my $self     = shift;
    my $args     = $self->parseparams( @_ );
    my $noDef    = $args->{NODEFAULT} || $args->{NODEFAULTS} || $args->{NODEF};
    my $defOnly  = $args->{DEFONLY} || $args->{DEFAULTONLY};
    my $argCase  = $self->{argumentCase};
    my %ignore;
    if (my $igReq = $args->{IGNORE} || $args->{SKIP}) {
        my @list = ref($igReq) ? @{$igReq} : ($igReq);
        map { $ignore{$self->param_alias($_)} = 1 } @list;
    }
    my @k;
    foreach my $key (sort keys %{$self}) {
        next unless (uc($key) eq $key);
        next if ($noDef && $self->is_default($key));
        next if ($defOnly && !$self->is_default($key));
        next if ($ignore{uc($key)});
        push @k, $argCase->{$key} || $key;
    }
    return wantarray ? @k : \@k;
}

sub copy {
    my $self = shift;
    my ($src, $force) = @_;
    foreach my $key ($src->all_keys()) {

        # WORK HERE

    }
    $self->death("copy() never implemented");
}

sub to_text {
    my $self = shift;
    my $text = "";
    my @keys = $self->all_keys( @_ );
    return $text if ($#keys == -1);
    my $args = $self->parseparams( @_ );
    $text = "# BMS::ArgumentParser Parameter Set\n";
    if (my $bq = $args->{BLOCKQUOTE}) {
        my @bqs = ref($bq) ? @{$bq} : ($bq);
        map { $self->blockquote($_, 1) } @bqs;
    }
    if (my $comReq = $args->{COMMENTS} || $args->{COMMENT} ||
        $args->{COM} || $args->{COMS}) {
        my @clist = ref($comReq) ? @{$comReq} : ($comReq);
        foreach my $com (@clist) {
            $com =~ s/[\n\r]/\n\# /g;
            $text .= "# $com\n";
        }
    }
    if (my $prot = $self->{ignoreParam}) {
        my $pt = join(" ", @{$prot}) || "";
        $pt =~ s/[\n\r]+/ /g;
        $text .= "# Some user-provided arguments were ignored as they are 'Default Only' protected:\n#  $pt\n" if ($pt);
    }
    my $isCompact = $args->{COMPACT};
    my $noBlank   = $args->{NONULL} || $args->{NOBLANK};
    my (@uv, @dv);
    foreach my $key (@keys) {
        if ($self->is_default($key)) {
            push @dv, $key;
        } else {
            push @uv, $key;
        }
    }
    my @types = ( "User supplied values", \@uv, 
                  "Default values defined by program", \@dv);
    for (my $d = 0; $d <= $#types; $d += 2) {
        $text .= "\n" unless ($isCompact);
        my $arr = $types[$d+1];
        next if ($#{$arr} == -1);
        $text .= "# ".$types[$d] . ":\n";
        foreach my $arg (@{$arr}) {
            my $val = $self->_val_to_text( $self->rawval($arg), undef, $arg );
            next if ($noBlank && $val eq '');
            $text .= "-$arg => $val\n";
            $text .= "\n" unless ($isCompact);
        }
    }
    return $text;
}

sub blockquote {
  my $self = shift;
  my $var  = shift;
  return undef unless ($var);
  $var = $self->param_alias($var);
  if (defined $_[0]) {
      $self->{blockQuote}{$var} = 
          !$_[0] ? 0 : $_[0] eq '1' ? 'BLOCKQUOTE' : $_[0];
  }
  return $self->{blockQuote}{$var};
}

my $joiner = "\\".'n'."\\"."\n";
my @splits = ("\n\r","\r\n", "\r", "\n");
sub _val_to_text {
    my $self = shift;
    my ($val, $qt, $arg) = @_;
    return "" unless (defined $val);
    my $ref = ref($val);
    my $bq = $self->blockquote($arg);
    if (!$ref) {
        # Scalar value
        my $rv;
        if ($bq) {
            $rv = "<<$bq;\n$val\n$bq";
        } else {
            my @parts = ($val);
            foreach my $sp (@splits) {
                @parts = map { split(/$sp/m, $_) } @parts;
            }
            $rv = join($joiner, @parts);
            if ($qt) {
                $rv =~ s/\Q$qt\E/\\$qt/g;
                $rv = $qt.$rv.$qt;
            }
        }
        return $rv;
    } elsif ($ref eq 'ARRAY') {
        if ($bq) {
            return "<<$bq;\n".join("\n", @{$val})."\n$bq";
        } else {
            return $self->_arr_to_text( $val );
        }
    } else {
        return $val;
    }
}

my $quote = '"';
sub _arr_to_text {
    my $self = shift;
    my $arr  = shift;
    my @bits;
    foreach my $val (@{$arr}) {
        push @bits, $self->_val_to_text( $val, $quote );
    }
    return "ARRAY[$quote][".(join(',', @bits) || "")."]";
}

*command_line = \&to_command_line;
sub to_command_line {
    my $self = shift;
    my @params;
    foreach my $key ($self->all_keys( @_ )) {
        push @params, $self->_single_key_to_command_param( $key );
    }
    return join(" ", @params) || "";
}

sub _single_key_to_command_param {
    my $self = shift;
    my ($key, $val) = @_;
    return "" unless ($key);
    $val = $self->rawval($key) unless (defined $val);
    return "" unless (defined $val);
    my $param = '-'.lc($key);
    if (my $r = ref($val)) {
        if ($r eq 'ARRAY') {
            return join(' ', map { 
                $self->_single_key_to_command_param($key, $_)
                } @{$val});
        } else {
            $self->msg("Can not parameterize $param '$val'");
            return "";
        }
    } elsif ($val eq '1') {
        return $param;
    } elsif ($val eq "") {
        $val = '""';
    } elsif ($val =~ /[^a-z_\.\,0-9]/i) {
        $val =~ s/\"/\\\"/g;
        $val = "\"$val\"";
    }
    $val =~ s/\n/\\n/g;
    $val =~ s/\r/\\r/g;
    return "$param $val";
}

sub to_get_string {
    my $self = shift;
    my $args = $self->parseparams( @_ );
    my $keepBlank = $args->{KEEPBLANK};
    my $skip;
    if (my $sk = $args->{SKIP} || $args->{SKIPKEY}) {
        my @arr = ref($sk) ? @{$sk} : ($sk);
        $skip = { map { $self->param_alias($_) => 1 } @arr };
    }
    my @params;
    foreach my $key ($self->all_keys( @_ )) {
        next if ($skip && $skip->{uc($key)});
        if (my $ptxt = $self->_single_key_to_get_param
            ( $key, undef, $keepBlank )) {
            push @params, $ptxt;
        }
    }
    return join("&", @params) || "";
}

sub to_hash {
    my $self = shift;
    my %hash;
    foreach my $key ($self->all_keys( @_ )) {
        $hash{$key} = $self->rawval($key);
    }
    return wantarray ? %hash : \%hash;
}

sub _single_key_to_get_param {
    my $self = shift;
    my ($key, $val, $keepBlank) = @_;
    return "" unless ($key);
    $val = $self->rawval($key) unless (defined $val);
    return "" unless (defined $val);
    return "" if ($val eq '' && !$keepBlank);
    my $param = lc($key);
    if (my $r = ref($val)) {
        if ($r eq 'ARRAY') {
            return join('&', map { 
                $self->_single_key_to_command_param($key, $_)
                } @{$val});
        } else {
            $self->msg("Can not parameterize $param '$val'");
            return "";
        }
    }
    return "$param=".$self->esc_url($val);
}

sub export {
    my $self = shift;
    my @keys = $self->all_keys( @_ );
    my %hash = map { $_ => $self->rawval($_) } @keys;
    return wantarray ? %hash : \%hash;
}

sub tiddly_link {
    my $self = shift;
    my ($tiddler, $name, $class) = @_;
    return "" unless ($tiddler);
    my $hurl = $self->val(qw(tiddlywiki)) || "Help";
    $hurl .= ".html" unless ($hurl =~ /html$/i);
    $name  ||= '[?]';
    $class   = 'twhelp' unless (defined $class);
    my $url  = sprintf
        ("<a class='%s' href='%s#%s' title='Help for %s' onclick=\"var win = window.open(this.href, '_help', 'width=900,toolbar=no,scrollbars=yes'); win.focus(); return false;\">%s</a>", 
         $class, $hurl,  $self->esc_url($tiddler), 
         $self->esc_xml_attr($tiddler), $self->esc_xml($name));
    return $url;
}

