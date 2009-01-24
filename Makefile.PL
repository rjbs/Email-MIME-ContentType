use 5.006; # why?  -- rjbs, 2006-11-20
use strict;
use ExtUtils::MakeMaker;

WriteMakefile(
  NAME              => 'Email::MIME::ContentType',
  VERSION_FROM      => 'lib/Email/MIME/ContentType.pm',
  (eval { ExtUtils::MakeMaker->VERSION(6.21) } ? (LICENSE => 'perl') : ()),
  PREREQ_PM         => {},
  ($] >= 5.005 ?
    (ABSTRACT_FROM  => 'lib/Email/MIME/ContentType.pm',
     AUTHOR         => 'Simon Cozens <simon@nonet>') : ()),
  (eval { ExtUtils::MakeMaker->VERSION(6.46) }
    ? (META_MERGE => {
        resources => {
          Repository => 'http://github.com/rjbs/email-mime-contenttype'
        }
      })
    : ()
  ),
);
