package GPS::Lowrance;

use 5.006;
use strict;
use warnings;

my ($OS_win, $SerialModule);

BEGIN{
  $OS_win = ($^O eq "MSWin32") ? 1 : 0;

  $SerialModule = ($OS_win)? "Win32::SerialPort" : "Device::SerialPort";

  eval "use $SerialModule;";
}

use Carp::Assert;
use Geo::Coordinates::MercatorMeters;
use GPS::Lowrance::LSI 0.23;
use GPS::Lowrance::Trail 0.21;
use Parse::Binary::FixedFormat;

# require Exporter;
# use AutoLoader qw(AUTOLOAD);

# our @ISA = qw(Exporter);

# our %EXPORT_TAGS = ( 'all' => [ qw(
	
# ) ] );

# our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

# our @EXPORT = qw(
	
# );

our $VERSION = '0.01';

our $AUTOLOAD;

use constant BUFF_READ_SZ  => 1024;
use constant BUFF_WRITE_SZ => 1024;

# Constants used for _make_method() routine

use constant CACHE         => 1;        # flag: cache output from GPS
use constant NO_CACHE      => 0;        # flag: do not cache output

use constant RAW_BUFFER    => 1;        # flag: do not decode buffer

my %ALLOWED_PARAMS = map { $_ => 1, } (qw(
  device baudrate parity databits stopbits readbuffer writebuffer
  debug timeout retrycount
));

sub connect {

  my $self  = {
    port         => undef,
    device       => undef,
    quiet        => 0,
    baudrate     => 9600,
    parity       => "none",
    databits     => 8,
    stopbits     => 1,
    binary       => 't',
    debug        => 0,
    timeout      => 2,
    retrycount   => 5,
    readbuffer   => BUFF_READ_SZ,
    writebuffer   => BUFF_WRITE_SZ,
  };
  my $class = shift;

  my %config = @_;
  foreach my $param (keys %config) {
    if ($ALLOWED_PARAMS{$param}) {
      $self->{$param} = $config{$param};
    } else {
      die "Unrecognized parameter: ``$param\'\'";
    }
  }

  bless $self, $class;

  unless ($self->_open_port) { return; }

  $self->{ProductInfo} = $self->get_product_info;

  return $self;
}

sub disconnect {
  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  if ($self->{port}) {
    $self->{port}->close; }
}

sub _open_port {
  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  $self->{port} = new $SerialModule( map {$self->{$_}} (qw( device quiet )) );

  foreach my $setting (qw( baudrate parity databits stopbits binary )) {
    my $method = $setting;
    $self->{port}->$method ($self->{$setting});
  }
  $self->{port}->buffers( $self->{readbuffer}, $self->{writebuffer} );
  $self->{port}->write_settings;

  return $self->{port};
}

sub query {
  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  my ($cmd, $data) = @_;

  return lsi_query($self->{port}, $cmd, $data, 0,
		   $self->{debug},
		   $self->{timeout}, $self->{retrycount}
		  );
}


sub _make_method {
  my ($cmd, $input_fmt, $output_fmt, $cache ) = @_;

  my ($input_parser, $output_parser, $output_sub);

  if ($input_fmt) {
    assert( ref($input_fmt) eq "ARRAY" ), if DEBUG;
    $input_parser = new Parse::Binary::FixedFormat $input_fmt;
  }
  
  if ($output_fmt) {
    if (ref($output_fmt) eq "ARRAY") {
      $output_parser = new Parse::Binary::FixedFormat $output_fmt;
      $output_sub = sub {
	return $output_parser->unformat( substr(shift,8) );
      };
    } else {
      $output_sub = sub {
	return substr(shift, 9, -1);
      };
    }
  }

  no strict 'refs';

  return sub {
    my $self = shift;
    assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

    if ($cache) {
      if (defined $self->{Cache}->{$cmd}) {
	return $self->{Cache}->{$cmd};
      }
    }

    my $data  = "";
    if ($input_fmt) {
      my %input = @_;
      $data     = $input_parser->format( \%input );
    }

    my $buff  = $self->query( $cmd, $data );

    unless (defined $buff) { return; }

    my $response = { };

    if ($output_fmt) {
      $response = &$output_sub( $buff );
    }

    if ($cache) {
      $self->{Cache}->{$cmd} = $response;
    }

    return $response;  
  }
}


BEGIN {

  *get_product_description    = _make_method( 0x0004, undef, RAW_BUFFER,
     NO_CACHE );

  *read_memory_location       = _make_method( 0x0008, [
      qw( address:V count:v cartridge_select:C ) ], RAW_BUFFER,
     NO_CACHE );

  *login_to_serial_port       = _make_method( 0x000d, undef, [
        qw( reserved:C checksum:C )
  ], NO_CACHE );

  *request_screen_pointer     = _make_method( 0x0301, undef, [
        qw( pixel_x:v pixel_y:v black_address:V black_count:v
	    grey_address:V grey_count:v )
  ], NO_CACHE );

  *unfreeze_current_unit_screen = _make_method( 0x0302, undef, undef,
     NO_CACHE );

  *get_icon_symbol            = _make_method( 0x0309, [
        qw( icon_number:v ) ], [
        qw( reserved:C icon_number:v latitude:l longitude:l icon_symbol:C )
  ], NO_CACHE );

  *get_product_info           = _make_method( 0x030e, undef, [
	qw( reserved:C product_id:v protocol_version:v
	    screen_type:v screen_width:v screen_height:v
	    num_of_waypoints:v num_of_icons:v num_of_routes:v
            num_of_waypoints_per_route:v
	    num_of_plottrails:C num_of_icon_symbols:C screen_rotate_angle:C
	    run_time:V checksum:C )
  ], CACHE );

  *get_plot_trail_origin      = _make_method( 0x0312, [
        qw( plot_trail_number:C ) ], [
        qw( reserved:C plot_trail_number:C
	  origin_x:l origin_y:l number_of_deltas:v )
  ], NO_CACHE );

  *get_plot_trail_deltas      = _make_method( 0x0313, [
        qw( plot_trail_number:C number_of_deltas:v ) ], [
        ( qw( reserved:C plot_trail_number:C number_of_deltas:v ),
          (map { ("delta_x_$_:s", "delta_y_$_:s",) } (1..40) ) )
  ], NO_CACHE );

}


sub read_memory {
  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  my %input = @_;

  my $count = $input{count} || 0;
  my $data  = "";

  while ($count) {
    $input{count}    = ($count>256) ? 256 : $count;
    $count          -= $input{count};

    my $buff         = $self->read_memory_location( %input );

    if (length($buff) != $input{count}) {
      die "Unable to read memory"; }

    $data           .= $buff;
    $input{address} += $input{count};
  }

  return $data;
}

sub get_plot_trail {
  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  my %input  = @_;
  my $origin = $self->get_plot_trail_origin( %input );

  my ($origin_x, $origin_y, $delta_count) =
    map { ( $origin->{$_} ) } (
     qw( origin_x origin_y number_of_deltas ) );

  my $trail = new GPS::Lowrance::Trail;

  $trail->trail_num( 1 + $input{plot_trail_number} );
  $trail->add_point( mercator_meters_to_degrees( $origin_x, $origin_y ) );

  while ($delta_count) {
    $input{number_of_deltas} = ($delta_count > 40) ? 40 : $delta_count;
    $delta_count -= $input{number_of_deltas};

    my $deltas = $self->get_plot_trail_deltas(%input);

    die "unable to retrieve deltas",
      unless ($deltas->{number_of_deltas} == $input{number_of_deltas});

    for my $i (1 .. $input{number_of_deltas}) {
      my ($x, $y) = map { ( $deltas->{$_."_$i"}||0 ) } (
        qw( delta_x delta_y ) );
      $origin_x += $x;
      $origin_y += $y;
      $trail->add_point( mercator_meters_to_degrees( $origin_x, $origin_y) );
    }

  }

  return $trail;
}

sub AUTOLOAD {
  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  $AUTOLOAD =~ /.*::get_([_\w]+)/
    or die "No such method: $AUTOLOAD";

  # Any item in ProductInfo is a valid attribute to request

  if (exists $self->{Cache}->{0x030e}->{$1}) {
    return $self->{Cache}->{0x030e}->{$1};
  } else {
    die "No such method: $1";
  }

}

sub DESTROY {
  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

}

1;
__END__

=head1 NAME

GPS::Lowrance - Connect to Lowrance and Eagle GPS devices

=head1 REQUIREMENTS

The following modules are required to use this module:

  Carp::Assert
  Parse::Binary::FixedFormat
  GPS::Lowrance::LSI
  GPS::Lowrance::Trail
  Win32::SerialPort or Device::SerialPort

This module should work with Perl 5.6.x. It has been tested on Perl 5.8.2.

=head2 Installation

Installation is standard:

  perl Makefile.PL
  make
  make test
  make install

For Windows playforms, you may need to use C<nmake> instead.

=head1 SYNOPSIS

  use GPS::Lowrance;
  use GPS::Lowrace::Trail;

  $gps = GPS::Lowrance->connect(
            Device     => 'com1',
            BaudRate   => 57600,
          );

  $trail = $gps->get_plot_trail( plot_trail_number => 0 );

  $gps->disconnect;

=head1 DESCRIPTION

This module provides a variety of higher-level methods for
communicating with Lowrance and Eagle GPS receivers.

=head1 METHODS

=over

=item connect

  $gps = GPS::Lowrance->connect(
            device     => $device_name,
            baudrate   => $baud_rate,
            parity     => $parity,
            databits   => $data_bits,
            stopbits   => $stop_bits,
            debug      => $debug_flag,
            timeout    => $timeout,
            retrycount => $retry_count,
  );

This method initiates the connection to the GPS and requests L<product
information|/get_product_information> from the unit.

=item query

  $data_out = $gps->query( $cmd, $data_in );

This is a wrapper for the L<GPS::Lowrance::LSI/lsi_query|lsi_query>
method in C<GPS::Lowrance::LSI>.

=item get_product_info

  $hashref = $gps->get_product_info

This method is called when there is a successful connection.  All data
is cached for subsequent calls.

=item get_protocol_version

  $ver = $gps->get_protocol_version;

Returns the protocol version.  Known values are:

  0 = Version 1.0
  1 = Version 2.0

The value is based on the original call to L</get_product_information>.

=item get_product_id

  $prod_id = $gps->get_product_id;

Returns the product identifier.  Known values are as follows:

   1 = GlobalMap        8 = Expedition II
   2 = AirMap           9 = GlobalNav 212
   3 = AccuMap         10 = GlobalMap 12
   4 = GlobalNav 310
   5 = Eagle View      12 = AccuMap 12
   6 = Eagle Explorer
   7 = GlobalNav 200   14 = GlobalMap 100

The value is based on the original call to L</get_product_information>.
 
=item get_screen_type

  $scn_type = $gps->get_screen_type;

The meaning of the return values:

   0 = Black pane only
   1 = Black and Grey Pane
   2 = Packed Pixel

The value is based on the original call to L</get_product_information>.

=item get_screen_width

  $width = 1 + $gps->get_screen_width;

Returns the width of the screen (minus 1).

The value is based on the original call to L</get_product_information>.

=item get_screen_height

  $height = 1 + $gps->get_screen_height;

Returns the height of the screen (minus 1).

The value is based on the original call to L</get_product_information>.

=item get_num_of_waypoints

  $num = $gps->get_num_of_waypoints;

Returns the maximum number of waypoints that the unit can store.

The value is based on the original call to L</get_product_information>.

=item get_num_of_icons

  $num = $gps->get_num_of_icons;

Returns the maximum number of icons that the unit can store.

The value is based on the original call to L</get_product_information>.

=item get_num_of_routes

  $num = $gps->get_num_of_routes;

Returns the maximum number of routes that the unit can store.

The value is based on the original call to L</get_product_information>.

=item get_num_of_waypoints_per_route

  $num = $gps->get_num_of_waypoints_per_route;

Returns the maximum number of waypoints that a route can contain.

The value is based on the original call to L</get_product_information>.

=item get_num_of_plottrails

  $num = $gps->get_num_of_plottrails;

Returns the maximum number of plot trails (e.g. breadcrumb trails)
that a unit can store.

The value is based on the original call to L</get_product_information>.

=item get_num_of_icon_symbols

  $num = $gps->get_num_of_icon_symbols;

Get the maximum number of icon symbols that the device can support.

The value is based on the original call to L</get_product_information>.

=item get_screen_rotate_angle

  $angle = $gps->get_screen_rotate_angle;

Returns the screen rotation angle (0, 90, 180, or 270).

The value is based on the original call to L</get_product_information>.

=item get_run_time

  $time = $gps->get_run_time;

Returns the run time of the unit (in seconds).

The value is based on the original call to L</get_product_information>.

=item get_product_description

  $name = $gps->get_product_description

Returns a short (less than 256 character) description of the product.

The value of this is cached for subsequent calls.

This is not an officially documented function, and it may not be
supported in all units (see L</Unsupported Functions> below).

=item read_memory_location

  $data = $gps->read_memory_location(
     address          => $addr,
     count            => $size,
     cartridge_select => $cart );

Reads C<$size> bytes from the memory location in cartridge C<$cart>. A
maximum of 256 bytes can be read.  If you need to read larger blocks,
use L</read_memory> instead.

C<$cart> is either 1 or 2.

=item read_memory

  $data = $gps->read_memory_location(
     address          => $addr,
     count            => $size,
     cartridge_select => $cart );

Reads C<$size> bytes from the memory location in cartridge C<$cart>.

C<$cart> is either 1 or 2.

=item login_to_serial_port

  $hash_ref = $gps->login_to_serial_port;

=item request_screen_pointer

  $hash_ref = $gps->request_screen_pointer;

Freezes the GPS display for downloading and returns pointers.  TheGPS will
be locked until there is a call to L</unfreeze_current_unit_screen>.

=item unfreeze_current_unit_screen

  $gps->unfreeze_current_unit_screen;

Called to unlock the GPS display.

=item get_plot_trail_origin

This only works for devices that understand I<protocol version 2>
(L</get_protocol_version> == 1).

=item get_plot_trail_deltas

This only works for devices that understand I<protocol version 2>
(L</get_protocol_version> == 1).

=item get_plot_trail

  $trail = $gps->get_plot_trail( plot_trail_number => $num );

Retrieves the trail specified by C<$num> (which is zero-based) as a
C<GPS::Lowrance::Trail> object.

It uses L</get_plot_trail_origin> and L</get_plot_trail_deltas> to
retrieve plot trails, and convert the data to Latitude and Logitude.
Thus it only works for devices that understand I<protocol version 2>
(L</get_protocol_version> == 1).

=item disconnect

  $gps->disconnect;

Disconnects the serial connection.

=back

=head1 CAVEATS

This is a beta version of the module, so there are bound to be some bugs.
In the current form it is also far from complete.

This module was tested with C<Win32::SerialPort>, although it should
use C<Device::SerialPort> on non-Windows platforms.  However, this has
not yet been tested.

=head2 Known Issues

The protocol uses little-endian values, and due to some quirks in the
decoding functions, they may not be converted properly on big-endian
machines.

=head2 Unsupported Functions

Because devices vary, there is no way to ensure that every device will
work with every function.

GPS units may not respond if they do not support or understand a
specific command.  In most cases the functions will time out and
return C<undef> after several retries.

=head1 SEE ALSO

The Lowrance Serial Interface (LSI) 100 Protocol is described in a
document available on the L<Lowrance|http://www.lowrance.com> or
L<Eagle|http://www.eaglegps.com> web sites, such as at
L<http://www.lowrance.com/Software/CyberCom_LSI100/cybercom_lsi100.asp>
or L<http://www.eaglegps.com/Downloads/Software/CyberCom/default.htm>.
(Note that the specific URLs are subject to change.)

A low-level implementation is available in

  GPS::Lowrance::LSI

=head2 Other GPS Vendors

There are other Perl modules to communicate with different GPS brands:

  GPS::Garmin
  GPS::Magellan

=head1 AUTHOR

Robert Rothenberg <rrwo at cpan.org>

=head2 Suggestions and Bug Reporting

Feedback is always welcome.  Please report any bugs using the CPAN
Request Tracker at L<http://rt.cpan.org>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Robert Rothenberg <rrwo at cpan.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=cut
