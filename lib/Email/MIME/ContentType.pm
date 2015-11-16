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

# For documentation, really:
my $special_re   = qr/[\x00-\x19\(\)<>\@,;:\\"\/\[\]?=]/;
my $unspecial_re = qr/[^\x00-\x19\(\)<>\@,;:\\"\/\[\]?=]/;
my $type_re      = qr/[^\x00-\x19\(\)<>\@,;:\\"\/\[\]?=]+/;
my $params       = qr/;.*/;

sub __default_ct {
  return {
    type    => 'text',  discrete  => 'text',
    subtype => 'plain', composite => 'plain',
    attributes => { charset => 'us-ascii' }
  }
}

sub parse_content_type { # XXX This does not take note of RFC2822 comments
  my $ct = shift;

  # If the header isn't there or is empty, give default answer.
  return __default_ct() unless defined $ct and length $ct;

  my ($base, $params)  = split m{;\s*}, $ct, 2;
  my ($type, $subtype) = split m{/}, lc $base, 2;

  # It is also recommend (sic.) that this default be assumed when a
  # syntactically invalid Content-Type header field is encountered. - RFC2045
  return __default_ct() if $type =~ $special_re or $subtype =~ $special_re;

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
    while (defined and length) {
        my ($name, $rest) = split /\s*=\s*/, $_, 2;
        $_ = $rest;

        if ($STRICT_PARAMS and $name =~ /$special_re/) {
          # We check for $_'s truth because some mail software generates a
          # Content-Type like this: "Content-Type: text/plain;"
          # RFC 1521 section 3 says a parameter must exist if there is a
          # semicolon.
          carp "Illegal Content-Type parameter $_" if $STRICT_PARAMS and $_;
          return $attribs;
        }

        my $attribute = lc $name;
        my $value = _extract_ct_attribute_value();
        $attribs->{$attribute} = $value;
    }
    return $attribs;
}

sub _extract_ct_attribute_value { # EXPECTS AND MODIFIES $_
    if (s/\A($type_re);?\s*//) {
      return $1;
    }

    if (/\A(["'])/) {
      s/\A$1([^$1]+)$1;?\s*//;
      return $1;
    }

    if (/($special_re+)/) {
      carp "Unquoted $1 not allowed in Content-Type!";
      return;
    }

    return;
}

sub build_content_type {
  my ($content_type) = @_;

  for my $req (qw(type subtype)) {
    croak "Invalid Content-Type: missing value for $_"
      unless my $v = $content_type->{$req};

    croak "Illegal value for Content-Type $req value: $v"
      unless $v =~ $type_re
  }

  my $content_type_str = "$content_type->{type}/$content_type->{subtype}";
  for my $k (keys %{$content_type->{attributes}}) {
    my $v = $content_type->{attributes}->{$k};
    next unless $v;
    # param names are RFC2045 `token`
    # param values are token / quoted-string
    $content_type_str .= "; $k=$v";
  }
  return $content_type_str;
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
