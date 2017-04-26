use strict;
use warnings;
package Email::MIME::ContentType;
# ABSTRACT: Parse a MIME Content-Type Header

use Carp;
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

=cut

our $STRICT_PARAMS = 1;

my $tspecials = quotemeta '()<>@,;:\\"/[]?=';
my $token = qr/[^$tspecials \x01-\x08\x0B\x0C\x0E\x1F]+/;
my $ct_default = 'text/plain; charset=us-ascii';
my $extract_quoted =
    qr/(?:\"(?:[^\\\"]*(?:\\.[^\\\"]*)*)\"|\'(?:[^\\\']*(?:\\.[^\\\']*)*)\')/;

  sub parse_content_type { # XXX This does not take note of RFC2822 comments
      my $ct = shift;

      # If the header isn't there or is empty, give default answer.
      return parse_content_type($ct_default) unless defined $ct and length $ct;

      # It is also recommend (sic.) that this default be assumed when a
      # syntactically invalid Content-Type header field is encountered.
      unless ($ct =~ s/^($token)\/($token)//) {
          carp "Invalid Content-Type '$ct'";
          return parse_content_type($ct_default);
      }

      my ($type, $subtype) = (lc $1, lc $2);

      $ct =~ s/\s+$//;
      my $params = $ct;

      return {
          type       => $type,
          subtype    => $subtype,
          attributes => _parse_attributes($params),

          # This is dumb.  Really really dumb.  For backcompat. -- rjbs,
          # 2013-08-10
          discrete   => $type,
          composite  => $subtype,
      };
  }

sub _parse_attributes {
    local $_ = shift;
    my $attribs = {};
    while (length $_) {
        s/^;// or $STRICT_PARAMS and do {
            carp "Missing semicolon before Content-Type parameter '$_'";
            return $attribs;
        };
        s/^\s+//;
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
        s/^\s+//;
        my $value = _extract_ct_attribute_value();
        $attribs->{$attribute} = $value;
    }
    return $attribs;
}

sub _extract_ct_attribute_value { # EXPECTS AND MODIFIES $_
    my $value;
    while (length $_) {
        if (s/^($token)//) {
            $value .= $1;
        } elsif (s/^($extract_quoted)//) {
            my $sub = $1; $sub =~ s/^["']//; $sub =~ s/["']$//;
            $value .= $sub;
        } elsif ($STRICT_PARAMS) {
            my $char = substr $_, 0, 1;
            carp "Unquoted '$char' not allowed in Content-Type";
            return;
        }
        my $erased = s/^\s+//;
        last if !length $_ or /^;/;
        if ($STRICT_PARAMS) {
            my $char = substr $_, 0, 1;
            carp "Extra '$char' found after Content-Type parameter";
            return;
        }
        if ($erased) {
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
2045. It returns a hash as above, with entries for the type, the subtype, and a
hash of attributes.

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
