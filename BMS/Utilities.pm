package BMS::Utilities;

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
use Time::HiRes;
use vars qw($ignoredErrors);

our $hkeyNS  = 'BMS_UTIL_'; # Hopefully unique hash key prefix
our $defaultMessageCB = sub {
    my ($self, $lines) = @_;
    my $msg  = "";
    return $msg if (!$lines || $#{$lines} == -1);
    my $firstTok = '*';
    my $pad      = "";
    if ($lines->[0] =~ /^(\s*)(\[([^\]]+)\])?$/) {
        # User-specified token and/or padding
        $firstTok = $3 || "";
        $pad      = $1 || "";
        shift @{$lines};
#    } elsif ($lines->[0] =~ /^\s*$/) {
#        # User request for no token, or simply padding
#        $firstTok = shift @{$lines};
    }
    return if ($firstTok eq 'IGNORE');
    $firstTok = ((!defined $firstTok) || $firstTok eq "") ? "" :
        $firstTok =~ /^\s+$/ ? $firstTok : "[$firstTok]";
    my $tokPad   .= (" " x length($firstTok)) || "";
    for my $i (0..$#{$lines}) {
        $msg .= sprintf("%s%s %s\n", $pad, $i ? $tokPad : $firstTok,
                        defined $lines->[$i] ? $lines->[$i] : '');
    }
    if (my $cb = $self->manage_callback('FormatCallback')) {
        $msg = &{$cb}( $self, $msg );
    }
    if (my $fh = $self->message_output()) {
        print $fh $msg;
    }
    return $msg;
};
our $defaultErrorCB = sub {
    my ($self, $lines) = @_;
    my $firstTok = '[!]';
    if ($#{$lines} == -1) {
        $lines = [ "Anonymous Error - no details!" ];
    } elsif ($lines->[0] && $lines->[0] =~ /^\[([^\]]+)\]$/) {
        $firstTok = shift @{$lines};
    }
    my @pass;
    my %params = ( addStack => 3, maxStack => 0 );

    foreach my $txt (@{$lines}) {
        $txt = "-UNDEF-" unless (defined $txt);
        foreach my $line (split(/[\n\r]/, $txt)) {
            next unless ($line);
            if ($line =~ /NO_STACK/) {
                # User does not want to see a stack dump in the error
                $line =~ s/NO_STACK//g;
                $params{noStack} = 1;
                push @pass, $line if ($line);
            } else {
                if ($line =~ /STACK_([\+\-\#]?\d+)\s*(.*)/) {
                    # User wants to offset the stack history
                    my $mod = $1;
                    $line   = $2;
                    if ($mod =~ /^[\+\-]/) {
                        # Relative offset
                        $params{addStack} ||= 0;
                        $params{addStack} += $mod;
                    } elsif ($mod =~ /^\#(\d+)/) {
                        # Single stack point
                        $params{addStack} = $params{maxStack} = $1;
                    } else {
                        # Absolute offset
                        $params{addStack} = $mod + 0;
                    }
                } elsif ($params{noStack} && $line =~ /^STACK:/) {
                    # BioPerl stack
                    next;
                }
                push @pass, $line;
            }
        }
    }
    
    if (defined $params{addStack} && ! $params{noStack}) {
        my $stack = $self->stack_trace($params{addStack}, $params{maxStack});
        push @pass, split("\n", $stack);
    }
    # push @pass, map { "FOO: $_ => $params{$_}" } sort keys %params;
    # 2010-08-02 : Change $cb, this might be a bad idea?
    # my $cb = $defaultMessageCB;
    my $rv = "";
    if (my $cb = $self->msg_callback()) {
        $rv = &{$cb}( $self, [$firstTok, @pass ] );
    } else {
        # If the callback is set to a false value just use built-in warn:
        $rv = join("\n", @pass);
        warn $rv;
    }
    return $rv;
};

our $globalUtilityPreferences = {
    MessageCallback => $defaultMessageCB,
    ErrorCallback   => $defaultErrorCB,
    DeathCallback   => $defaultErrorCB,
};

=head2 new

 Title   : new
 Usage   : my $obj = BMS::Utilities->new();
 Function: Generate a new object
 Returns : a BMS::Utilities object
 Args    : 

This module will normally not be directly instantiated, but instead
will be ISAed by an inheriting module. However, new( ) is provided to
allow simple objects to be created in case these methods are desired
in vacuo.

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    bless ($self, $class);
    return $self;
}

=head2 parseparams

 Title   : parseparams
 Usage   : my $paramHash = $obj->parseparams(@args)
 Function: Borrowed from Bio::Parse.pm, who borrowed it from CGI.pm
           Lincoln Stein -> Richard Resnick -> here
 Returns : A hash reference of the parameter keys (uppercase) pointing to
           their values.
 Args    : An array of key / value pairs

Standardizes parameters into a hash reference with upper case hash
keys representing paramter names, and hash values the coresponding
parameter values. Leading dashes will be stripped from parameter
names, allowing usage in the form of:

    my $args = $obj->parseparams( -color => 'blue', -size => 'small' );

=cut

*parse_params = \&parseparams;
sub parseparams {
    my $self  = shift;
    my %hash  = ();
    my @param = @_;
    unless ($#param % 2) {
        # There should always be an even number of entries in @_
        $self->err("Odd element length parameter list:", map {
            "[$_] ". (defined $param[$_] ? "'$param[$_]'" : "-UNDEF-")
            } (0..$#param));
	push @param, undef;
    }
    
    # Hacked out from Parse.pm
    # The next few lines strip out the '-' characters which
    # preceed the keys, and capitalizes them.
    for (my $i = 0 ; $i < @param; $i += 2) {
        $param[$i] =~ s/^\-+//;
        $param[$i] =~ tr/a-z/A-Z/;
    }
    (%hash) = @param;
    return \%hash;
}

=head2 argv_hash

 Title   : argv_hash
 Usage   : my %hash = $obj->argv_hash()
 Function: Standardizes @ARGV to a hash
 Returns : A hash or hash reference, depending on calling context
 Args    : None

The method is simply designed to standardize @ARGV into a hash similar
to that generated by parseparams(). The method expects parameter names
to be preceded by a dash. If the word following a parameter name also
starts with a dash, it is assumed to be another parameter, and the
value for the current parameter will be set to 1 (one). Multiple
parameters with the same name may be passed; the value for that
parameter will then be an array reference. So, the following command
line:

  -color blue -size 4 -size 10 -tepid -size cinammon

... will result in a return value of:

  COLOR => 'blue',
  SIZE  => ['4','10', 'cinammon'],
  TEPID => 1

=cut

sub argv_hash {
    my $self   = shift;
    my @passed = @ARGV;
    my %hash;
    while ($#passed != -1) {
        my $arg = shift @passed;
        if ($arg =~ /^\-(.+)/) {
            # Settings indicated by -blahblah
            $arg = $1;
            my $val = $#passed == -1 ? 1 : shift @passed;
            # $val    = 1 unless (defined $val && $val ne "");
            if ($val =~ /^\-/) {
                # Oops, shifted off another parameter name
                # Put it back:
                unshift @passed, $val;
                # And presume that the parameter is just a flag:
                $val = 1;
            }
            push @{$hash{uc($arg)}}, $val;
        }
    }
    # De-array keys with single entries
    foreach my $key (keys %hash) {
        $hash{$key} = $hash{$key}[0] if ($#{$hash{$key}} == 0);
    }
    return wantarray ? %hash : \%hash;
}

=head2 message_output

 Title   : message_output
 Usage   : my $fh = $obj->message_output($newValue);
 Function: Sets / gets the target stream for default messages
 Returns : A filehandle, or undef
 Args    : [0] Optional new value

This method guides the destination of the output for the default
messaging callbacks. It is initially set to STDERR, but can be changed
to other destinations by passing a new value. Passing a file handle
will direct output there. Alternatively, one of the following strings
can be passed:

  err : STDERR
  out : STDOUT
  null : Discard output

=cut

our $msgPipe = *STDERR;
sub message_output {
    my $self = shift;
    if (defined $_[0]) {
        my $oReq = $_[0];
        if (ref($oReq) || $oReq =~ /^\*main::STD/) {
            $msgPipe = $oReq;
        } elsif ($oReq =~ /err/i) {
            $msgPipe = *STDERR;
        } elsif ($oReq =~ /out/) {
            $msgPipe = *STDOUT;
        } elsif ($oReq =~ /(null|quiet)/i) {
            $msgPipe = undef;
        } elsif (!$oReq) {
            $msgPipe = 0;
        } else {
            # http://stackoverflow.com/questions/3214647/what-is-the-best-way-to-determine-if-a-scalar-holds-a-filehandle
            $@ = "";
            my $t = eval { fileno $oReq };
            if (!$@ && defined $t) {
                $msgPipe = $oReq; 
            } else {
                $self->err
                    ("Can not determine where to pipe messages given '$oReq'");
            }
        }
    }
    return $msgPipe;
}

=head2 manage_callback

 Title   : manage_callback
 Usage   : my $codeRef = $obj->manage_callback($key, $newVal, $setGlobal)
 Function: Sets / gets the callback method for a particular key
 Returns : A subroutine reference, or undef
 Args    : [0] The key (a string) the callback is stored under
           [1] Optional new callback (subroutine reference)
           [2] Flag to set the new value as the global default

This method manages callback designation and retrieval for a handful
of methods, notably msg() and err(). It can be called directly, but it
is likely easier to use the appropriate wrapper methods msg_callback()
and err_callback(). The function requires the hash key that stores the
callback. The second argument can be used to provide a new value for
the callback, while the third determines if the new value should apply
to the calling object, or be set as a default.

Passing a newvalue of zero (0) will remove the callback.

The function will return the current callback. If the object has a
specific callback set, then it will be returned; otherwise, the global
callback, if available, will be returned.

=cut

my $callbackList = {}; # Was using $self, but caused problems with DBI
sub manage_callback {
    my $self = shift;
    my ($hkey, $newVal, $setGlobal) = @_;
    return undef unless ($hkey);
    if (defined $newVal) {
        # The user is altering the callback
        if (my $r = ref($newVal)) {
            if ($r eq 'CODE') {
                if ($setGlobal) {
                    # Set the global default
                    $globalUtilityPreferences->{$hkey} = $newVal;
                } else {
                    # Set a callback for this object only
                    $callbackList->{$hkeyNS.$hkey} = $newVal;
                }
            } else {
                $self->err("Callback for $hkey must be set with a code reference, not '$r'");
            }
        } else {
            if ($newVal) {
                $self->err("Callback for $hkey must be set with a code reference, not a scalar");
            } elsif ($setGlobal) {
                # The global callback is being cleared
                delete $globalUtilityPreferences->{$hkey};
            } else {
                delete $callbackList->{$hkeyNS.$hkey};
            }
        }
    }
    return $callbackList->{$hkeyNS.$hkey} || $globalUtilityPreferences->{$hkey};
}

=head2 msg

 Title   : msg
 Usage   : $obj->msg( @details )
 Function: Emit a message
 Returns : The message text
 Args    : One or more strings

The nature in which the message will be handled depends on the
callback function set by msg_callback(). The default is to perform
some rudimentary formatting and warn( ) the content.

=cut

sub msg {
    my $self = shift;
    if (my $cb = $self->msg_callback()) {
        return &{$cb}( $self, [ @_ ] );
    }
    return undef;
}

our $spoken_messages = {};
sub msg_once {
    my $self = shift;
    my $key  = join("\t", map { defined $_ ? $_ : "" } @_) || "";
    return undef if ($spoken_messages->{$key}++);
    return $self->msg(@_);
}

=head2 msg_callback

 Title   : msg_callback
 Usage   : my $cb = $obj->msg_callback($newValue, $setGlobal)
 Function: Sets / gets the callback method for processing messages
 Returns : A subroutine reference, or undef
 Args    : [0] Optional new callback (subroutine reference)
           [1] Flag to set the new value as the global default

When msg() is called, the callback will be passed the calling object,
and an array reference of 'message content', presumably strings.

=cut

sub msg_callback {
    my $self = shift;
    return $self->manage_callback('MessageCallback', @_);
}

=head2 err

 Title   : err
 Usage   : $obj->err( @details )
 Function: Emit an error message
 Returns : The message text
 Args    : One or more strings

The nature in which the message will be handled depends on the
callback function set by err_callback(). The default is to perform
some rudimentary formatting and warn( ) the content, along with a
stack trace dump.

=cut

sub err {
    my $self = shift;
    my $rv;
    if ($self->{private_noLoopError}++) {
        # Prevent looping
    } elsif (my $reason = $self->skip_error(@_)) {
        # print "Ignoring = $reason\n".$self->stack_trace().join(" + ", map {defined $_ ? $_ : '-undef-' } @_)."----\n";
        $rv = $reason;
    } elsif (my $cb = $self->err_callback()) {
        $rv = &{$cb}( $self, [ @_ ] );
    }
    $self->{private_noLoopError} = 0;
    return $rv;
}

=head2 death

 Title   : death
 Usage   : $obj->death( @details )
 Function: Emit an error and exit
 Returns : Exits, return an exit code if provided
 Args    : One or more strings, optional error code at the end

Similar to err(), but will also halt execution. The "DeathCallback"
function will be used to control the behavior. If the last argument is
an integer, it will be used as an exit code (otherwise 0 will be
used).

=cut

sub death {
    my $self = shift;
    my $eCode = -1;
    if ($#_ != -1 && defined $_[-1] && $_[-1] =~ /^\d+$/) {
        $eCode = pop @_;
    }
    my $doNotDie = 0;
    my $txt = join("\n", @_);
    if (my $cb = $self->manage_callback('DeathCallback')) {
        $txt = &{$cb}( $self, [ @_ ] );
        $doNotDie++ if ($txt && $txt =~ /NODEATH/);
    }
    return "NODEATH" if ($doNotDie);
    $self->_mail_on_death( $txt );
    exit $eCode;
}

sub ignore_error {
    my $self = shift;
    my ($txt, $delete) = @_;
    return unless ($txt);
    my $re;
    if ($txt =~ /^\/(.+)\/$/) {
        $txt = $1;
        $re = qr/$1/;
    } else {
        $re  = qr/\Q$txt\E/;
    }
    unless ($ignoredErrors) {
        return unless ($self->can('intercept_errors'));
        $ignoredErrors = {};
        $self->intercept_errors();
    }
    if ($delete) {
        delete $ignoredErrors->{$txt};
    } else {
        $ignoredErrors->{$txt} = $re;
    }
}

sub skip_error {
    my $self = shift;
    return 0 unless ($ignoredErrors);
    foreach my $txt (@_) {
        next unless (defined $txt);
        return "Explicit Ignore Request" if ($txt =~ /\[IGNORE\]/);
        foreach my $regexp (values %{$ignoredErrors || {}}) {
            return $regexp if ($regexp && $txt =~ /$regexp/);
        }
    }
    return 0;
}

=head2 err_callback

 Title   : err_callback
 Usage   : my $cb = $obj->err_callback($newValue, $setGlobal)
 Function: Sets / gets the callback method for processing messages
 Returns : A subroutine reference, or undef
 Args    : [0] Optional new callback (subroutine reference)
           [1] Flag to set the new value as the global default

When err() is called, the callback will be passed the calling object,
an array reference of 'error content' (presumably strings), and an
array reference corresponding to the stack trace.

=cut

sub err_callback {
    my $self = shift;
    return $self->manage_callback('ErrorCallback', @_);
}

=head2 stack_trace

 Title   : stack_trace
 Usage   : $obj->stack_trace( $depth, $maxDepth )
 Function: Extracts the stack trace for the current point in execution
 Returns : An array of data or string, depending on calling context
 Args    : [0] Optional starting stack depth (default 1)
           [1] Maximum depth to pursue (default 50)

In array context, an array of array references will be returned. Each
array ref is composed of:

 [ PackageName, Subroutine, LineNumber ]

In scalar context, a string will be returned, with each stack event on
one line, showing the subroutine and line number.

The optional depth allows earlier methods in the stack to be
ignored. The maximum depth prevents extensive traces through
recurrsion.

=cut


our $ignoredStackParts = {};
sub ignore_stack {
    my $self = shift;
    if (my $subname = shift) {
        $ignoredStackParts->{$subname} = 1;
    }
}

sub stack_trace {
    my $self     = shift;
    my $depth    = shift || 1;
    my $maxDepth = shift || 50;
    my @history;
    while (1) {
        my ($pack, $file, $j4, $subname) = caller($depth);
        my ($j1, $j2, $line) = caller($depth-1);
        last unless ($line);
        $subname ||= 'main';
        push @history, [$line, $subname, $pack]
            unless ($ignoredStackParts->{$subname});
        $depth++;
        last if ($depth > $maxDepth);
    }
    return @history if (wantarray);
    my $text = "";
    foreach my $dat (@history) {
        $text .= sprintf("    [%5d] %s\n", @{$dat});
    }
    return $text || ""; # '-No stack trace-';
}

our $debugObject;
sub debug {
    my $self = shift;
    unless (defined $debugObject) {
        # Only pull in this code when it is required
        require BMS::Utilities::Debug;
        $debugObject = BMS::Utilities::Debug->new();
    }
    return $debugObject;
}

*dump = \&branch;
sub branch { 
    my $self = shift;
    if (my $dobj = $self->debug()) {
        return $dobj->branch( @_ );
    }
    return "";
}

=head2 

 Title   : 
 Usage   : $obj->()
 Function: 
 Returns : 
 Args    : 

=cut


return 1;
