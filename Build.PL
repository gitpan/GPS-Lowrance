use Module::Build;

# Note: we need either Win32::SerialPort or Device::SerialPort,
# depending on your platform.  Both are not needed, so warnings can be
# ignored.

# my $OS_win = ($^O eq "MSWin32") ? 1 : 0;
# my $SerialModule = ($OS_win)? "Win32::SerialPort" : "Device::SerialPort";

my $build = Module::Build->new
    (
     module_name => 'GPS::Lowrance',
     license => 'perl',
     requires => {
       'perl'                       => '5.6.1',
       'Carp::Assert'               => 0,
       'GPS::Lowrance::LSI'         => 0.23,
       'Parse::Binary::FixedFormat' => 0.02,
#        $SerialModule                => 0,
     },
     recommends => {
       'GD'                         => 0,
       'Geo::Coordinates::UTM'      => 0,
       'Geo::Coordinates::DecimalDegrees' => 0,
       'XML::Generator'             => 0,
       'GPS::Lowrance::Trail'       => 0.41,
       'Win32::SerialPort'          => 0,
       'Device::SerialPort'         => 0,
     },
     autosplit => [qw( lib/GPS/Lowrance.pm )],
     create_makefile_pl => 'traditional',
     dist_author        => 'Robert Rothenberg <rrwo at cpan.org>',
);

$build->create_build_script;
