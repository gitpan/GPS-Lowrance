# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl GPS-Lowrance.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 5;
BEGIN { use_ok('Geo::Coordinates::MercatorMeters') };

#########################

use strict;

sub _round {
  my $a = shift;
  my $b = shift || 10000;
  return int( $a * $b ) / $b;
}

my ($lat_m, $lon_m) = (4976902, -8077507);

my ($lat,   $lon)   = mercator_meters_to_degrees( $lat_m, $lon_m );

ok( $lat,  40.8731870007440 );
ok( $lon, -72.8055832934594 );

my ($a, $b) = degrees_to_mercator_meters( $lat, $lon );

ok($a == $lat_m);
ok($b == $lon_m);
