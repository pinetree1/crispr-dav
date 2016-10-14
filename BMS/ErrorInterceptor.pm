# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
package BMS::ErrorInterceptor;
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

use strict;
use BMS::Utilities;


use vars qw(@ISA);
@ISA   = qw(BMS::Utilities);

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {
    };
    bless ($self, $class);
    return $self;
}

our $interceptingErrors = 0;
our @oldSigs;
sub intercept_errors {
    my $self = shift;
    my ($stopInt) = @_;
    if ($stopInt) {
        &_stop_intercept();
    } elsif (!$interceptingErrors) {
        @oldSigs = ($SIG{__WARN__}, $SIG{__DIE__});
        $SIG{__WARN__} = sub { return &_intercept_warn( $self, @_ ) };
        $SIG{__DIE__}  = sub { return &_intercept_die( $self, @_ ) };
        $interceptingErrors = 1;
        $self->ignore_stack("BMS::ErrorInterceptor::_intercept_die");
        $self->ignore_stack("BMS::ErrorInterceptor::__ANON__");

        if (my $etxt = $ENV{IGNORE_ERROR}) {
            # Environment variable is providing ignore strings
            foreach my $txt (split(/\n/, $etxt)) {
                $self->ignore_error($txt);
            }
        }
    }
    return $interceptingErrors;
}

sub _stop_intercept {
    if ($interceptingErrors) {
        ($SIG{__WARN__}, $SIG{__DIE__}) = @oldSigs;
        @oldSigs = ();
        $interceptingErrors = 0;
    }
}

sub DESTROY {
    # Whaaa?? Not sure what my rational is here?
    # The problem here is that one object shuts down intercept for all others
    # &_stop_intercept();
}

sub _intercept_warn {
    my $self  = shift;
    # In DESTROY calls $self can be undef
    return undef unless ($self);
    my ($txt) = @_;
    return undef unless ($txt);
    my $terminated = ($txt =~ /[\n\r]$/ && $txt !~ /line \d+( during global destruction)?\.?\s*[\n\r]*$/)
        ? 1 : 0;
    return undef if ($self->skip_error($txt));
    return undef if ($self->{INTERCEPTING}++);
    $txt =~ s/[\n\r]+$//;
    if ($terminated) {
        # If the message is return-terminated, treat it as a simple message
        $self->msg("[W]", $txt);
    } else {
        # Otherwise, treat as an error and show a full stack trace
        # STACK_+2 will discard the top two stack entries, these are:
        # _intercept_warn and __ANON__
        $self->err( "[WARN]", "STACK_+2", $txt );
    }
    delete $self->{INTERCEPTING};
    return undef;
}

our $stdErrState;
our $stdErrValues;
sub silence_stderr {
    my $self = shift;
    # http://stevesprogramming.blogspot.com/2010/10/temporarily-closing-stderr-in-perl.html
    unless ($stdErrState) {
        open($stdErrState, ">&", \*STDERR) || $self->death
            ("Can not capture STDERR", $!);
        close STDERR;
        $stdErrValues = "";
        open(STDERR, ">", \$stdErrValues) || $self->death
            ("Failed to point STDERR to variable", $!);
    }
    return $stdErrState;
}

sub restore_stderr {
    my $self = shift;
    if ($stdErrState) {
        close STDERR;
        open (STDERR, ">&", $stdErrState) || $self->death
            ("Can not restore STDERR", $!);
        close $stdErrState;
        select STDERR; $| = 1;
    }
    return $stdErrValues;
}

our $errorMail;
sub error_mail {
    my $self = shift;
    if (my $nv = shift) {
        $errorMail = $ENV{EI_ERRORMAIL} = $nv;
    }
    return $errorMail;
}

sub _intercept_die {
    my $self = shift;
    my ($txt, $rv) = @_;
    my $depth = 1;
    while (1) {
        my ($pack, $file, $j4, $subname) = caller($depth);
        # Do nothing for death called within eval() blocks
        # We will assume that whomever built the eval is also dealing with it
        if ($subname && $subname eq '(eval)') {
            #$self->msg("Ignoring fatal eval error", "".$self->stack_trace());
            return undef;
        }
        my ($j1, $j2, $line) = caller($depth-1);
        last unless ($line);
        last if ($depth++ > 1000);
    }
    $txt =~ s/\s*[\n\r]+$//;
    if ($self->skip_error($txt)) {
        # Internal die() will effectively re-write the STDERR message
        return undef;
    }
    if ($self->skip_error("Quiet Death")) {
        return undef;
    }

    my @bits = ( "FATAL ERROR!", $txt );
    push @bits, $self->_mail_on_death( $txt );
    $rv = $self->death( @bits );
    if ($rv && $rv eq 'NODEATH') {
        return undef;
    }
    return $rv;
}

sub _mail_on_death {
    my $self = shift;
    my $txt = shift;
    my $errorMail = $ENV{EI_ERRORMAIL};
    return () unless ($errorMail);
    return () if ($self->{MAILED_ALREADY}++);
    my @pbits = split(/\//, $0);
    my $subj  = "Death in $pbits[-1] for ".$self->user_name();
    my $mailBody = $txt;
    if (my $cb = $self->manage_callback('FormatCallback')) {
        $mailBody = &{$cb}( $self, join("\n",
                                        "FormatParam Mail=1",
                                        "FormatParam Report=1",
                                        $mailBody ));
    }
    $self->send_mail($mailBody, $subj, $errorMail, undef, undef, 1);
    return ("Administrators (<a href='mailto:$errorMail'>$errorMail</a>) have been notified.");
}


sub send_mail {
    my $self = shift;
    my ($msg, $subj, $to, $spamFile, $spamFreq, $doBP) = @_;
    # Often $self will be an instance of BMS::ArgumentParser ...
    # If so, we can get some defaults from global params via val()
    my $canVal = $self->can('val');
    $to  ||= ($canVal ? $self->val(qw(errmail errormail)) : "") || $errorMail;
    $msg ||= "ERROR: NO MESSAGE PROVIDED!";
    unless ($to) {
        $self->err("No to: provided in MAIL_MESSAGE()");
        return;
    }
    $spamFile ||= $canVal ? $self->val(qw(spamfile)) : '';
    $doBP     ||= $canVal ? $self->val(qw(detailmail)) : '';
    if ($spamFile) {
        my $age = (-e $spamFile) ? int(0.5 + 100 * (-M $spamFile)) / 100 : 999;
        if (open(SF, ">>$spamFile")) {
            print SF `date`;
            close SF;
            chmod(0666, $spamFile);
        } else {
            $msg .= "\nFAILED TO UPDATE SPAM FILE:\n  $spamFile\n  $!\n\n";
        }
        $spamFreq ||= 1/24;
        return $age ? $age : 0.01 if ($age < $spamFreq);
    }
    $to = join(',', @{$to}) if (ref($to));
    unless ($subj) {
        my @pbits = split(/\//, $0);
        $subj = "Message from program $pbits[-1]";
    }
    # REAL pain to set Content-Type in Mail
    # http://stackoverflow.com/questions/2591755/how-send-html-mail-using-linux-command-line/5822182#5822182
    my $cmd   = "| Mail -s \"\$(echo -e \"$subj\nContent-Type: text/html\")\" $to";
    $msg      = $self->mail_body( $msg ) if ($doBP);
    open (MAIL, $cmd);
    print MAIL $msg;
    close MAIL;
    return 0;
}

sub mail_body {
    my $self  = shift;
    my ($txt) = @_;
    
    my $user  = $self->user_name();
    my $msg = "<b>User :</b> $user<br />\n";
    $msg   .= "<b>Host :</b> ".($ENV{HTTP_HOST} || $ENV{HOST} || $ENV{HOSTNAME} || "--Unknown--")."<br />\n";
    $msg   .= "<b>URL  :</b> ".($ENV{REQUEST_URI} || $ENV{PWD} || "--Unknown--")."<br />\n";
    if ($self->isa('BMS::ArgumentParser')) {
        my $file = sprintf("/tmp/ParameterFile-%d-%d.param", time, $$);
        if (open(PF, ">$file")) {
            # Why am I referencing $self this way??
            print PF BMS::ArgumentParser::to_text
                ( $self, -ignore => ['NOCGI'] );
            close PF;
            $msg .= "<b>Param:</b> $file\n";
            my ($uri, $host) = ($ENV{REQUEST_URI},
                                $ENV{HTTP_HOST} || $ENV{SERVER_NAME});
            if ($uri && $host) {
                if ($uri =~ /(.+)\?/) { 
                    # If the URL already had a get string on the end,
                    # discard it in favor of the temp file
                    $uri = $1;
                }
                $msg .= "<b>Go   :</b> http://$host$uri?valuefile=$file\n<br />";
            }
        } else {
            $msg .= "\nFailed to write parameter file: $!\n$file\n<br />";
        }
    }
    $msg   .= "\n$txt\n" if ($txt);
    # Security does not want stack traces in mail:
    # $msg   .= $self->stack_trace(3);
    return $msg;
}

sub user_name {
    my $self = shift;
    return $self->ldap() if ($self->can('ldap'));
    return $ENV{'HTTP_MAIL'} || $ENV{'REMOTE_USER'} ||
        $ENV{'LDAP_USER'} || $ENV{'HTTP_CN'} ||
        $ENV{'USER'}      || $ENV{'LOGNAME'} || $ENV{'REMOTE_ADDR'} ||
        '';
}

1;
