# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
package BMS::Utilities::FileUtilities;
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
use BMS::Utilities::Escape;

use vars qw(@ISA);
@ISA   = qw(BMS::Utilities::Escape);

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {
    };
    bless ($self, $class);
    my $args = $self->parseparams( @_ );
    $self->url_callback( $args->{URLCB} );
    return $self;
}

our $globalUrlCallback = sub { return undef; };
sub url_callback {
    my $self = shift;
    if (defined $_[0]) {
        if (! $_[0]) {
            # zero, empty string = clear the callback
            $globalUrlCallback = sub { return shift; };
        } else {
            my $r = ref($_[0]) || "";
            if ($r =~ /CODE/) {
                $globalUrlCallback = $_[0];
            } else {
                $self->err("url_callback() must be set to a subroutine reference, not '$_[0]'");
            }
        }
    }
    return $globalUrlCallback;
}

sub path2url {
    my $self = shift;
    my $path = shift;
    my $cb   = $self->url_callback();
    return &{$cb}( $path );
}

sub path2link {
    my $self = shift;
    my ($path, $attr, $label) = @_;
    my $url  = $self->path2url($path);
    if ($url) {
        my $lnk = "<a";
        if ($attr) {
            # The user is providing HTML attributes
            if (my $r = ref($attr)) {
                if ($r eq 'HASH') {
                    foreach my $at (sort keys %{$attr}) {
                        $lnk .= sprintf(" %s='%s'", lc($at),
                                        $self->esc_xml($attr->{$at}));
                    }
                }
            } else {
                # literal string
                $lnk .= " $attr";
            }
        }
        $label ||= $path;
        $lnk .= " href='$url'>$label</a>";
        return $lnk;
    } else {
        return "<span style='font-family:monospace'>$path</span>";
    }
}

*assure_directory = \&assure_dir;
sub assure_dir {
    my $self = shift;
    my ($req, $isFile, $perm) = @_;
    # Determine if requested path is absolute or relative
    my $path  = $req =~ /^\// ? "" : ".";
    # Build an array of the needed directory tree:
    my @pbits = split(/\//, $req);
    # If request is full file name, we want to remove the terminal file name 
    pop @pbits if ($isFile);
    foreach my $part (@pbits) {
        next unless ($part);
        $path .= "/$part";
        # Do nothing if the path already exists
        next if (-d $path);
        if (mkdir($path)) {
            $perm ||= 0777;
            chmod($perm, $path);
        } else {
            $self->err("Failed to create directory",$path,$!);
            return undef;
        }
    }
    return $path;
}

sub read_dir {
    my $self = shift;
    unshift @_, '-dir' if ($#_ == 0);
    my $args = $self->parseparams( @_ );
    my $seed = $args->{DIR} || $args->{DIRECTORY};
    my $rec  = $args->{RECURSE} || $args->{RECURSIVE};
    my $dOnly = $args->{DIRONLY};
    my $keep = $args->{KEEP};
    my $toss = $args->{TOSS};
    $keep    = [$keep] if ($keep && !ref($keep));
    $toss    = [$toss] if ($toss && !ref($toss));
    my (@rv, @dirstack, %seendir);
    push @dirstack, ref($seed) ? @{$seed} : ($seed);
    while ($#dirstack != -1) {
        my $dir = shift @dirstack;
        next if (!defined $dir || $dir eq '');
        next if ($seendir{$dir}++);
        if (opendir(DIR, $dir)) {
            foreach my $file (readdir DIR) {
                next if ($file eq '.' || $file eq '..');
                my $path = "$dir/$file";
                if (-d $path) {
                    push @rv, $path if ($dOnly);
                    if ($rec) {
                        push @dirstack, $path;
                        next;
                    } elsif ($dOnly) {
                        next;
                    }
                } elsif ($dOnly) {
                    next;
                }
                my $keepit = 1;
                if ($keep) {
                    $keepit = 0;
                    foreach my $re (@{$keep}) {
                        if ($file =~ /$re/) {
                            $keepit = 1;
                            last;
                        }
                    }
                }
                if ($toss) {
                    foreach my $re (@{$toss}) {
                        if ($file =~ /$re/) {
                            $keepit = 0;
                            last;
                        }
                    }
                }
                push @rv, $path if ($keepit);
            }
            closedir DIR;
        } else {
            $self->err("Failed to read directory", $dir, $!)
                unless ($args->{QUIET});
        }
    }
    return wantarray ? @rv : \@rv;
}

sub module_path {
    my $self = shift;
    if ($#_ == -1) {
        return "";
    } elsif ($#_ == 0) {
        unshift @_, "-module";
    }
    my $key  = "";
    my $sfx  = "";
    my $args = $self->parseparams( @_ );
    if (my $mod  = $args->{MODULE}) {
        $key = ref($mod) || $mod;
        $key =~ s/\:\:/\//g;
        $sfx = "pm";
    }
    return "" unless $key;
    $key .= ".$sfx" if ($sfx && $key !~ /\.$sfx$/);
    my $path = "";
    if (exists $INC{$key}) {
        # The module is already installed
        $path = $INC{$key}
    } else {
        # Cycle through @INC and see if we can find it
        for my $i (0..$#INC) {
            my $dir = $INC[$i];
            if (-e "$dir/$key") {
                $path = "$dir/$key";
                last;
            }
        }
    }
    if (my $newSfx = $args->{SUFFIX}) {
        $path =~ s/\.\Q$sfx\E$/\.$newSfx/;
    }
    return $path;
}

sub file_is_older_than_module {
    my $self = shift;
    my $file = shift;
    return undef unless ($file);
    return -1 unless (-e $file);
    my @check = $#_ == -1 ? ($self) : @_;
    foreach my $mod (@check) {
        my $modF = -e $mod ? $mod : $self->module_path( $mod );
        return -1 unless ($modF && -e $modF);
        return 1 if (-M $file > -M $modF);
    }
    return 0;
}

sub file_is_older_than_days {
    my $self = shift;
    my $file = shift;
    return undef unless ($file);
    return -1 unless (-e $file);
    my $days = shift || 0;
    return 1 if (-M $file > $days);
    return 0;
}
