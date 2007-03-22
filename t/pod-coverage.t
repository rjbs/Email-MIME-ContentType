#!perl -T

use Test::More;
eval "use Test::Pod::Coverage 1.08";
plan skip_all => "Test::Pod::Coverage 1.08 required for testing POD coverage"
  if $@;

# XXX: actually document or privatize or REALLY be trustme
my $trustme = [ qw(fail_gracefully done_ok fail_badly noexit) ];

all_pod_coverage_ok({
  trustme => $trustme,
  coverage_class => 'Pod::Coverage::CountParents'
});
