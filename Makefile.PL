use 5.006;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'GPS::Lowrance',
    VERSION_FROM      => 'lib/GPS/Lowrance.pm', # finds $VERSION
    PREREQ_PM         => {
      'Carp::Assert'               => 0,
#      'Geo::Coordinates::UTM'      => 0.02, 
      'GPS::Lowrance::LSI'         => 0.23,
      'GPS::Lowrance::Trail'       => 0.21,
      'Parse::Binary::FixedFormat' => 0.02,
    }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/GPS/Lowrance.pm', # retrieve abstract from module
       AUTHOR         => 'Robert Rothenberg <rrwo at cpan.org>') : ()),
);
