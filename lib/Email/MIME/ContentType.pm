use strict;
use warnings;
package Email::MIME::ContentType;
# ABSTRACT: Parse a MIME Content-Type Header

use Carp;
use Encode 2.87 qw(find_mime_encoding);
use Exporter 5.57 'import';
our @EXPORT = qw(parse_content_type);

=head1 SYNOPSIS

  use Email::MIME::ContentType;

  # Content-Type: text/plain; charset="us-ascii"; format=flowed
  my $ct = 'text/plain; charset="us-ascii"; format=flowed';
  my $data = parse_content_type($ct);

  $data = {
    type       => "text",
    subtype    => "plain",
    attributes => {
      charset => "us-ascii",
      format  => "flowed"
    }
  };


  # Content-Type: application/x-stuff;
  #  title*0*=us-ascii'en'This%20is%20even%20more%20;
  #  title*1*=%2A%2A%2Afun%2A%2A%2A%20;
  #  title*2="isn't it!"
  my $ct = q(application/x-stuff;
   title*0*=us-ascii'en'This%20is%20even%20more%20;
   title*1*=%2A%2A%2Afun%2A%2A%2A%20;
   title*2="isn't it!");
  my $data = parse_content_type($ct);

  $data = {
    type       => "application",
    subtype    => "x-stuff",
    attributes => {
      title => "This is even more ***fun*** isn't it!"
    }
  };

=cut

our $STRICT_PARAMS = 1;

my $tspecials = quotemeta '()<>@,;:\\"/[]?=';
my $token = qr/[^$tspecials \x01-\x08\x0B\x0C\x0E\x1F]+/;
my $ct_default = 'text/plain; charset=us-ascii';
my $extract_quoted =
    qr/(?:\"(?:[^\\\"]*(?:\\.[^\\\"]*)*)\"|\'(?:[^\\\']*(?:\\.[^\\\']*)*)\')/;
my $re_charset = qr/[!"#\$%&'+\-0-9A-Z\\\^_`a-z\{\|\}~]+/;
my $re_language = qr/[A-Za-z]{1,8}(?:-[0-9A-Za-z]{1,8})*/;
my $exvalue = qr/($re_charset)?'(?:$re_language)?'(.*)/;

sub parse_content_type {
    my $ct = shift;

    # If the header isn't there or is empty, give default answer.
    return parse_content_type($ct_default) unless defined $ct and length $ct;

    _unfold_lines($ct);
    _clean_comments($ct);

    # It is also recommend (sic.) that this default be assumed when a
    # syntactically invalid Content-Type header field is encountered.
    unless ($ct =~ s/^($token)\/($token)//) {
        carp "Invalid Content-Type '$ct'";
        return parse_content_type($ct_default);
    }

    my ($type, $subtype) = (lc $1, lc $2);

    _clean_comments($ct);
    $ct =~ s/\s+$//;

    my $attributes = {};
    if ($STRICT_PARAMS and length $ct and $ct !~ /^;/) {
        carp "Missing semicolon before first Content-Type parameter '$ct'";
    } else {
        $attributes = _process_rfc2231(_parse_attributes($ct));
    }

    return {
        type       => $type,
        subtype    => $subtype,
        attributes => $attributes,

        # This is dumb.  Really really dumb.  For backcompat. -- rjbs,
        # 2013-08-10
        discrete   => $type,
        composite  => $subtype,
    };
}

sub _unfold_lines {
    $_[0] =~ s/(?:\r\n|[\r\n])(?=[ \t])//g;
}

sub _clean_comments {
    my $ret = ($_[0] =~ s/^\s+//);
    while (length $_[0]) {
        last unless $_[0] =~ s/^\(//;
        my $level = 1;
        while (length $_[0]) {
            my $ch = substr $_[0], 0, 1, '';
            if ($ch eq '(') {
                $level++;
            } elsif ($ch eq ')') {
                $level--;
                last if $level == 0;
            } elsif ($ch eq '\\') {
                substr $_[0], 0, 1, '';
            }
        }
        carp "Unbalanced comment in Content-Type" if $level != 0 and $STRICT_PARAMS;
        $ret |= ($_[0] =~ s/^\s+//);
    }
    return $ret;
}

sub _process_rfc2231 {
    my ($attribs) = @_;
    my %cont;
    my %encoded;
    foreach (keys %{$attribs}) {
        next unless $_ =~ m/^(.*)\*(\d+)\*?$/;
        my ($attr, $sec) = ($1, $2);
        $cont{$attr}->[$sec] = $attribs->{$_};
        $encoded{$attr}->[$sec] = 1 if $_ =~ m/\*$/;
        delete $attribs->{$_};
    }
    foreach (keys %cont) {
        my $key = $_;
        $key .= '*' if $encoded{$_};
        $attribs->{$key} = join '', @{$cont{$_}};
    }
    foreach (keys %{$attribs}) {
        next unless $_ =~ m/^(.*)\*$/;
        my $key = $1;
        next unless $attribs->{$_} =~ m/^$exvalue$/;
        my ($charset, $value) = ($1, $2);
        $value =~ s/%([0-9A-Fa-f]{2})/pack('C', hex($1))/eg;
        if (length $charset) {
            my $enc = find_mime_encoding($charset);
            if (defined $enc) {
                $value = $enc->decode($value);
            } else {
                carp "Unknown charset '$charset' in Content-Type value";
            }
        }
        $attribs->{$key} = $value;
        delete $attribs->{$_};
    }
    return $attribs;
}

sub _parse_attributes {
    local $_ = shift;
    substr($_, 0, 0, '; ') if length $_ and $_ !~ /^;/;
    my $attribs = {};
    while (length $_) {
        s/^;// or $STRICT_PARAMS and do {
            carp "Missing semicolon before Content-Type parameter '$_'";
            return $attribs;
        };
        _clean_comments($_);
        unless (length $_) {
            # Some mail software generates a Content-Type like this:
            # "Content-Type: text/plain;"
            # RFC 1521 section 3 says a parameter must exist if there is a
            # semicolon.
            carp "Extra semicolon after last Content-Type parameter" if $STRICT_PARAMS;
            return $attribs;
        }
        my $attribute;
        if (s/^($token)=//) {
            $attribute = lc $1;
        } else {
            if ($STRICT_PARAMS) {
                carp "Illegal Content-Type parameter '$_'";
                return $attribs;
            }
            unless (s/^([^;=\s]+)\s*=//) {
                carp "Cannot parse Content-Type parameter '$_'";
                return $attribs;
            }
            $attribute = lc $1;
        }
        _clean_comments($_);
        my $value = _extract_ct_attribute_value();
        $attribs->{$attribute} = $value;
        _clean_comments($_);
    }
    return $attribs;
}

sub _extract_ct_attribute_value { # EXPECTS AND MODIFIES $_
    my $value;
    while (length $_) {
        if (s/^($token)//) {
            $value .= $1;
        } elsif (s/^($extract_quoted)//) {
            my $sub = $1;
            $sub =~ s/^["']//;
            $sub =~ s/["']$//;
            $sub =~ s/\\(.)/$1/g;
            $value .= $sub;
        } elsif ($STRICT_PARAMS) {
            my $char = substr $_, 0, 1;
            carp "Unquoted '$char' not allowed in Content-Type";
            return;
        }
        my $erased = _clean_comments($_);
        last if !length $_ or /^;/;
        if ($STRICT_PARAMS) {
            my $char = substr $_, 0, 1;
            carp "Extra '$char' found after Content-Type parameter";
            return;
        }
        if ($erased) {
            # Sometimes semicolon is missing, so check for = char
            last if m/^$token=/;
            $value .= ' ';
        }
        $value .= substr $_, 0, 1, '';
    }
    return $value;
}

1;

=func parse_content_type

This routine is exported by default.

This routine parses email content type headers according to section 5.1 of RFC
2045 and also RFC 2231 (Character Set and Parameter Continuations).  It returns
a hash as above, with entries for the C<type>, the C<subtype>, and a hash of
C<attributes>.

For backward compatibility with a really unfortunate misunderstanding of RFC
2045 by the early implementors of this module, C<discrete> and C<composite> are
also present in the returned hashref, with the values of C<type> and C<subtype>
respectively.

=head1 WARNINGS

This is not a valid content-type header, according to both RFC 1521 and RFC
2045:

  Content-Type: type/subtype;

If a semicolon appears, a parameter must.  C<parse_content_type> will carp if
it encounters a header of this type, but you can suppress this by setting
C<$Email::MIME::ContentType::STRICT_PARAMS> to a false value.  Please consider
localizing this assignment!

=cut
