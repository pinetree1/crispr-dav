# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
package BMS::Utilities::Escape;
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
#use URI::Escape;

use vars qw(@ISA);
@ISA   = qw(BMS::Utilities);

our @xesc = ( amp  => '&',
              quot => '"',
              apos => "'",
              gt   => '>',
              lt   => '<',);

# What about ???  '#10' => '\n' 

our @uesc = ( '%' => '25',
              ' ' => '20',
              '<' => '3C',
              '>' => '3E',
              '#' => '23',
              '{' => '7B',
              '}' => '7D',
              '|' => '7C',
              '\\' => '5C',
              '^' => '5E',
              '~' => '7E',
              '[' => '5B',
              ']' => '5D',
              '`' => '60',
              ';' => '3B',
              '/' => '2F',
              '?' => '3F',
              ':' => '3A',
              '@' => '40',
              '=' => '3D',
              '&' => '26',
              '$' => '24', );




sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {
    };
    bless ($self, $class);
    return $self;
}

sub esc_xml_and_whitespace {
    my $val  = &esc_xml(@_);
    # Extending to include all low-code non-printing and whitespace:
    $val =~ s/[\x00-\x1F\x7F]/ /g;
    return $val;
}

sub esc_xml {
    my $self = shift;
    my $val  = shift;
    return "" unless (defined $val);
    for (my $i = 0; $i < $#xesc; $i += 2) {
        $val =~ s/$xesc[$i+1]/\&$xesc[$i]\;/g;
    }
    return $val;
}

*esc_html_attr = \&esc_xml_attr;
sub esc_xml_attr {
    # Should this be different?
    return &esc_xml_and_whitespace( @_ );
}

sub esc_url {
    my $self = shift;
    my $val  = shift;
    return "" unless (defined $val);
    return uri_escape( $val );
}

sub esc_url_keep_slash {
    my $self = shift;
    return join('/', map { $self->esc_url($_) } split(/\//, shift));
}

sub esc_text {
    my $self = shift;
    my ($val, $forceQuotes) = @_;
    return $forceQuotes ? '""' : "" unless (defined $val);
    $val =~ s/\\/\\\\/g;
    $val =~ s/\"/\\\"/g;
    $val =~ s/\n/\\n/g;
    $val =~ s/\r/\\r/g;
    $val =~ s/\t/\\t/g;
    return ($forceQuotes || $val =~ /[\'\"\s]/) ? "\"$val\"" : $val;
}

sub esc_js {
    my $self = shift;
    my $html = shift;
    if (defined $html) {
        $html =~ s/\\/\\\\/g;
        $html =~ s/\"/\\\"/g;
        $html =~ s/[\n\r]/\\n/g;
    } else {
        $html = "";
    } 
    return $html;
}

my $needToEscRe = { map { $_ => 1 } split('',"\\(){}[]^\$.+?") };

sub esc_regexp {
    my $self = shift;
    my $txt  = shift;
    return "" unless ($txt);
    my @chars = split('', $txt);
    my @esc;
    while ($#chars != -1) {
        my $char = shift;
        push @esc, "\\" if ($needToEscRe->{$char});
        push @esc, $char;
    }
    return join('', @esc);
}
