# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl GPS-Lowrance.t'

#########################

use Test::More tests => 22;
BEGIN { use_ok('GPS::Lowrance') };

# verify conversion routines

ok( GPS::Lowrance::GPS_DATE_OFFSET == 694242000 );

ok( gps_to_unix_time( 0 ) == GPS::Lowrance::GPS_DATE_OFFSET );
ok( unix_to_gps_time( GPS::Lowrance::GPS_DATE_OFFSET ) == 0 );

for my $i (-3..3) {
  my $s = unpack "S", pack "s", $i;
  ok( signed_int($s) == $i );
  my $l = unpack "L", pack "l", $i;
  ok( signed_long($l) == $i );
}

# Verify LSI constants

ok( GPS::Lowrance::MAX_DELTAS == 40 );
ok( GPS::Lowrance::MAX_BYTES  == 256 );

# Verify other constants

ok( GPS::Lowrance::CACHE );
ok(!GPS::Lowrance::NO_CACHE );

#########################

__END__

# Below is only used for development. Real test cases need to be written.

use strict;

require Data::Dumper;

my $gps = GPS::Lowrance->connect(
            device     => 'com1',
            baudrate   => 57600,
            debug      => 1,
            timeout    => 2,
            retrycount => 0,
          );

my $info = $gps->get_product_info;
print STDERR Data::Dumper->Dump([$info],['info']);

$gps->login_to_serial_port;

# print STDERR $gps->get_product_id, "\n";

# print STDERR $gps->get_product_description, "\n";

# use GPS::Lowrance::Screen;
# use GD;

# $info = $gps->get_number_of_graphical_symbols;
# print STDERR Data::Dumper->Dump([$info],['info']);

# $info = $gps->get_graphical_symbol_info( icon_symbol_index => 14, );
# print STDERR Data::Dumper->Dump([$info],['info']);

# my $img = get_graphical_symbol( $gps, icon_symbol_index => 14, );

# my $fo = new FileHandle ">foo.png";
# binmode $fo; print $fo $img->png; $fo->close;


# $img = get_current_screen( $gps );

# $fo = new FileHandle ">bar.png";
# binmode $fo; print $fo $img->png; $fo->close;

# my $img = get_current_screen( $gps, undef, [128,0,0], [255,255,255] );


# $info = $gps->get_a_waypoint(  waypoint_number => 11 );
# print STDERR Data::Dumper->Dump([$info],['info']);



# use GPS::Lowrance::Trail;
# use GPS::Lowrance::Waypoints;

# sub callback {
#   my $info = shift;
#   print STDERR $info, "\r";
# }

# my $wpt = $gps->get_waypoints( callback => \&callback, waypoints => [1..4] );

# $wpt->write_utm( \*STDERR );

# $wpt = $gps->get_waypoints( callback => \&callback, waypoints => [5..8] );
# $wpt->write_utm( \*STDERR );

# $gps->set_waypoints( callback => \&callback, waypoints => $wpt );

# my $wpt = $gps->get_waypoints( callback => \&callback, waypoints => [1..4] );

# $wpt->write_gpx( \*STDERR );


# # print STDERR $gps->get_protocol_version, "\n";

# my $trail = $gps->get_plot_trail( plot_trail_number => 1,
#   callback => \&callback );

# $trail->trail_num(1);

# $gps->set_plot_trail( plot_trail => $trail, callback => \&callback );

# $trail = $gps->get_plot_trail( plot_trail_number => 0 );
# $trail->write_latlon( \*STDERR );

# $info = $gps->get_plot_trail_pointer( plot_trail_number => 0, );
#print STDERR Data::Dumper->Dump([$info],['info']);

$gps->disconnect;
