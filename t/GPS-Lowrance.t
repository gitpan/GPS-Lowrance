# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl GPS-Lowrance.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 1;
BEGIN { use_ok('GPS::Lowrance') };

#########################

__END__

# Below is only used for development. Read test cases need to be written.

use strict;

require Data::Dumper;

my $gps = GPS::Lowrance->connect(
            device     => 'com1',
            baudrate   => 57600,
            debug      => 1,
            timeout    => 2,
            retrycount => 1,
          );

my $info = $gps->get_product_info;
print STDERR Data::Dumper->Dump([$info],['info']);

# print STDERR $gps->get_product_id, "\n";

print STDERR $gps->get_product_description, "\n";


# $info = $gps->request_screen_pointer;
# print STDERR Data::Dumper->Dump([$info],['info']);

# my $data = $gps->read_memory(
#              address => $info->{grey_address},
# 	     count => $info->{grey_count}, cartridge_select => 1 );

# print STDERR length($data), "\n";

# $gps->unfreeze_current_unit_screen; # why timeout?

# $gps->login_to_serial_port;

# $info = $gps->get_icon_symbol( icon_number => 0 );

# print STDERR Data::Dumper->Dump([$info],['info']);

# $info = $gps->get_plot_trail_origin( plot_trail_number => 0 );

# print STDERR Data::Dumper->Dump([$info],['info']);

# $info = $gps->get_plot_trail_deltas( plot_trail_number => 0, number_of_deltas => 40, );

# print STDERR Data::Dumper->Dump([$info],['info']);

# $info = $gps->get_plot_trail_deltas( plot_trail_number => 0, number_of_deltas => 40, );

# print STDERR Data::Dumper->Dump([$info],['info']);

use GPS::Lowrance::Trail;

my $trail = $gps->get_plot_trail( plot_trail_number => 0 );

my $fh = new FileHandle ">foo.txt";

$trail->write_lonlat( $fh );

$fh->close;


$gps->disconnect;
