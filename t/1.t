# vim:ft=perl
use Test::More 'no_plan';
use_ok("Email::MIME::ContentType");
Email::MIME::ContentType->import("parse_content_type");
my %ct_tests = (
    "application/foo" => 
        { discrete => "application", composite => "foo", attributes=>{} },
    "multipart/mixed; boundary=unique-boundary-1" => 
        { discrete => "multipart", composite => "mixed",
          attributes => { boundary => "unique-boundary-1" }
        },
    'message/external-body; access-type=local-file; name="/u/nsb/Me.jpeg"' =>
        { discrete => "message", composite => "external-body",
          attributes => { "access-type" => "local-file",
                          "name"        => "/u/nsb/Me.jpeg" }
        },
    '' => { discrete => "text", composite => "plain", 
            attributes => { charset => "us-ascii" } },
    'multipart/mixed; boundary="----------=_1026452699-10321-0" ' => {
              'discrete' => 'multipart',
              'composite' => 'mixed',
              'attributes' => {
                                'boundary' => '----------=_1026452699-10321-0'
                              }
           },
);

for (sort keys %ct_tests) {
    is_deeply(parse_content_type($_), $ct_tests{$_}, "Can parse C-T $_");
}
