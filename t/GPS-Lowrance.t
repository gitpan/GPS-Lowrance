# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl GPS-Lowrance.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 3;
BEGIN { use_ok('GPS::Lowrance') };

ok( gps_to_unix_time( 0 ) == 694242000 );
ok( unix_to_gps_time( 694242000 ) == 0 );

#########################

__END__

# Below is only used for development. Real test cases need to be written.

use strict;

require Data::Dumper;

my $gps = GPS::Lowrance->connect(
            device     => 'com1',
            baudrate   => 57600,
            debug      => 0,
            timeout    => 2,
            retrycount => 1,
          );

my $info = $gps->get_product_info;
print STDERR Data::Dumper->Dump([$info],['info']);

print STDERR $gps->get_product_id, "\n";

print STDERR $gps->get_product_description, "\n";

# use GPS::Lowrance::Screen;
# use GD;

# my $img = get_current_screen( $gps, undef, [128,0,0], [255,255,255] );

# my $fo = new FileHandle ">foo.png";
# binmode $fo; print $fo $img->png; $fo->close;

$info = $gps->get_a_waypoint(  waypoint_number => 7 );
print STDERR Data::Dumper->Dump([$info],['info']);

print STDERR scalar(localtime(gps_to_unix_time($info->{date}))), "\n",
     join(",", mercator_meters_to_degrees( $info->{latitude}, $info->{longitude} ) ), "\n";


# $info->{waypoint_number} = 13;

# $info->{date} = time - 694242000;
# $info->{name} = "PerlTest";

# $gps->set_a_waypoint( %$info );

# $info = $gps->get_waypoint(  waypoint_number => $info->{waypoint_number} );
# print STDERR Data::Dumper->Dump([$info],['info']);


# $gps->login_to_serial_port;

# $info = $gps->get_icon_symbol( icon_number => 0 );
# print STDERR Data::Dumper->Dump([$info],['info']);

# $info = $gps->get_plot_trail_origin( plot_trail_number => 0 );
# print STDERR Data::Dumper->Dump([$info],['info']);
# $info = $gps->get_plot_trail_deltas( plot_trail_number => 0, number_of_deltas => 40, );
# print STDERR Data::Dumper->Dump([$info],['info']);
# $info = $gps->get_plot_trail_deltas( plot_trail_number => 0, number_of_deltas => 40, );
# print STDERR Data::Dumper->Dump([$info],['info']);

# use GPS::Lowrance::Trail;
# my $trail = $gps->get_plot_trail( plot_trail_number => 0 );
# my $fh = new FileHandle ">foo.txt";
# $trail->write_lonlat( $fh );
# $fh->close;


$gps->disconnect;
