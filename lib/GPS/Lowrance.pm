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

no Carp::Assert;
use Geo::Coordinates::MercatorMeters;
use GPS::Lowrance::LSI 0.23;
use Parse::Binary::FixedFormat;

# use GPS::Lowrance::Trail 0.41;
# use GPS::Lowrance::Waypoints;

require Exporter;
use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

our @EXPORT = (
  @Geo::Coordinates::MercatorMeters::EXPORT,
  qw( gps_to_unix_time unix_to_gps_time signed_long signed_int )
);

our %EXPORT_TAGS = (
  'all' => [ @EXPORT ],
);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our $VERSION = '0.30';

our $AUTOLOAD;

use constant GPS_DATE_OFFSET => 694242000;

sub gps_to_unix_time {
  my $time = shift;
  return $time + GPS_DATE_OFFSET;
}

sub unix_to_gps_time {
  my $time = shift;
  assert( $time >= GPS_DATE_OFFSET ), if DEBUG;
  return $time - GPS_DATE_OFFSET;
}

# SerialPort constants

use constant BUFF_READ_SZ  => 1024;
use constant BUFF_WRITE_SZ => 1024;

# Constants used for _make_method() routine

use constant CACHE         => 1;        # flag: cache output from GPS
use constant NO_CACHE      => 0;        # flag: do not cache output

use constant RAW_BUFFER    => 1;        # flag: do not decode buffer

# LSI constants

use constant MAX_DELTAS    => 40;       # max trail deltas to download
use constant MAX_BYTES     => GPS::Lowrance::LSI::MAX_BYTES;

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

# We have our own signed_long and signed_int routines because pack
# and unpack only support unsigned longs and integers which are
# machine independent ("Vaxian" order).

sub signed_long {
  my $n = shift;
  assert ($n <= 0xffffffff), if DEBUG;
  if ($n >= 0x80000000) {
    return -(0xffffffff - $n + 1);
  } else {
    return $n;
  }
}

sub signed_int {
  my $n = shift;
  assert( $n <= 0xffff ), if DEBUG;
  if ($n >= 0x8000) {
    return -(0x10000 - $n);
  } else {
    return $n;
  }
}


sub _make_method {
  my ($cmd, $input_fmt, $output_fmt, $cache, $input_cvt, $output_cvt ) = @_;

  # Make a method to handle low-level GPS functions.  Since most of
  # the code is repetative, we have one subroutine which creates the
  # code based on the parameters:
  #
  # $cmd        = LSI protocol command
  # $input_fmt  = input format (see Parse::Binary::FixedFormat)
  # $output_fmt = output format
  # $cache      = flag: true means cache output until disconnect
  # $input_cvt  = values to convert to signed
  # $output_cvt = values to convert to signed

  my ($input_parser, $output_parser, $output_sub);

  if ($input_fmt) {
    assert( ref($input_fmt) eq "ARRAY" ), if DEBUG;
    $input_parser = new Parse::Binary::FixedFormat $input_fmt;
  }


  # KLUGE: There is no machine-independent way to handle signed ints
  # and longs using pack and unpack.  Instead we use unsigned ints and
  # logs and convert them.

  sub _convert_unsigned_to_signed {
    my ($output, $output_cvt) = @_;
    assert( ref($output_cvt) eq "ARRAY" ), if DEBUG;
    foreach my $field (@$output_cvt) {
      my ($fname, $ftype) = split /:/, $field;
      if (defined $output->{$fname}) {
	if ($ftype eq "v") {
	  $output->{$fname} = signed_int( $output->{$fname} );
	} elsif ($ftype eq "V") {
	  $output->{$fname} = signed_long( $output->{$fname} );
	} else {
	  die "Don\'t know what to do with ``$field\'\'";
	}
      }
    }
    return $output;
  }
  
  if ($output_fmt) {
    if (ref($output_fmt) eq "ARRAY") {
      $output_parser = new Parse::Binary::FixedFormat $output_fmt;
      $output_sub = sub {
	my $output = $output_parser->unformat( substr(shift,8) );

	# Convert unsigned values to signed values
	if ($output_cvt) {
	  $output = _convert_unsigned_to_signed( $output, $output_cvt );
	}
	return $output;
      };
    } else {
      assert(!defined $output_cvt), if DEBUG;
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
      if ($input_cvt) {
	%input  = %{ _convert_unsigned_to_signed( \%input, $input_cvt ) };
      }
      $data     = $input_parser->format( \%input );
    } else {
      assert( !defined $input_cvt ), if DEBUG;
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

sub _unimplemented {
  die "This method is not yet implemented";
}

BEGIN {

  *get_product_description    = _make_method( 0x0004, undef, RAW_BUFFER,
     CACHE );

  *read_memory_location       = _make_method( 0x0008, [
      qw( address:V count:v cartridge_select:C ) ], RAW_BUFFER,
     NO_CACHE );

  *write_memory_location      = *_unimplemented; # 0x0009

  *login_to_serial_port       = _make_method( 0x000d, undef, [
        qw( reserved:C checksum:C )
  ], NO_CACHE );

  *login_to_nmea_serial_port  = *login_to_serial_port;

  *change_baud_rate           = *_unimplemented; # 0x010a

  *request_screen_pointer     = _make_method( 0x0301, undef, [
        qw( pixel_x:v pixel_y:v black_address:V black_count:v
	    grey_address:V grey_count:v )
  ], NO_CACHE );

  *unfreeze_current_unit_screen = _make_method( 0x0302, undef, undef,
     NO_CACHE );

  *get_a_waypoint               = _make_method( 0x0303, [
        qw( waypoint_number:v ) ], [
        qw( reserved:C waypoint_number:v status:C icon_symbol:C
	    latitude:V longitude:V name:A13 date:V )
  ], NO_CACHE,
        undef, [
        qw( latitude:V longitude:V )] );

  *set_a_waypoint               = _make_method( 0x0304, [
        qw( waypoint_number:v status:C icon_symbol:C
	    latitude:V longitude:V name:A13 date:V ) ], undef,
     NO_CACHE, [
        qw( latitude:V longitude:V )], undef );

  *send_a_waypoint              = *set_a_waypoint;

  # Note: GPS dates are the number of seconds since 00:00 Jan 1,
  # 1992. So take the GPS date and add 694242000 to convert to Unix
  # time.

  *get_a_route                  = *_unimplemented; # 0x0305

  *set_a_route                  = *_unimplemented; # 0x0305

  *send_a_route                 = *get_a_route;

  *get_plot_trail_pointer       = _make_method( 0x0307, [
        qw( plot_trail_number:C ) ], [
        qw( reserved:C plot_trail_number:C
	    structure_pointer:V structure_size:V )
  ], NO_CACHE );

  # Protocol Version 2.0 devices may not respond to get_plot_trail_pointer.

  *get_number_of_icons          = _make_method( 0x0308, undef, [
        qw( reserved:C number_of_icons:v )
  ], NO_CACHE );

  *get_icon_symbol              = _make_method( 0x0309, [
        qw( icon_number:v ) ], [
        qw( reserved:C icon_number:v latitude:V longitude:V icon_symbol:C )
  ], NO_CACHE );

  *set_number_of_icons          = _make_method( 0x030a, [
        qw( number_of_icons:v ) ], undef,
     NO_CACHE );

  *set_icon_symbol              = *_unimplemented; # 0x030b

  *send_icon                    = *set_icon_symbol;

  *get_number_of_graphical_symbols = _make_method( 0x030c, undef, [
        qw( reserved:C number_of_symbols:C )
  ], CACHE );

  # Note: LSI 100 v1.1 documents says number_of_symbols is a word.

  *get_graphical_symbol_info       = _make_method( 0x030d, [
        qw( icon_symbol_index:v ) ], [
        qw( reserved:C icon_symbol_index:C
            width:C height:C bytes_per_symbol:C 
	    structure_pointer:V )
  ], NO_CACHE );

  # Note: LSI 100 v1.1 document leaves out the returned icon_symbol_index.

  *get_product_info                = _make_method( 0x030e, undef, [
	qw( reserved:C product_id:v protocol_version:v
	    screen_type:v screen_width:v screen_height:v
	    num_of_waypoints:v num_of_icons:v num_of_routes:v
            num_of_waypoints_per_route:v
	    num_of_plot_trails:C num_of_icon_symbols:C screen_rotate_angle:C
	    run_time:V )
  ], CACHE );

  foreach my $attribute (qw(product_id protocol_version
	    screen_type screen_width screen_height
	    num_of_waypoints num_of_icons num_of_routes
            num_of_waypoints_per_route
	    num_of_plot_trails num_of_icon_symbols screen_rotate_angle
	    run_time )) {
    no strict 'refs';
    my $method = "get_" . $attribute;
    *$method   = sub {
      my $self = shift;
      assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;
      return $self->{Cache}->{0x030e}->{$attribute};
    }
  }

  *get_plot_trail_origin           = _make_method( 0x0312, [
        qw( plot_trail_number:C ) ], [
        qw( reserved:C plot_trail_number:C
	  origin_y:V origin_x:V number_of_deltas:v )
  ], NO_CACHE,
        undef, [
        qw( origin_y:V origin_x:V ) ] );

  *get_plot_trail_deltas         = _make_method( 0x0313, [
        qw( plot_trail_number:C number_of_deltas:v ) ], [
        ( qw( reserved:C plot_trail_number:C number_of_deltas:v ),
          (map { ("delta_y_$_:v", "delta_x_$_:v",) } (1..MAX_DELTAS) ) )
  ], NO_CACHE,
        undef, [
          (map { ("delta_y_$_:v", "delta_x_$_:v",) } (1..MAX_DELTAS) )
  ] );

  *set_plot_trail_origin           = _make_method( 0x0314, [
        qw( plot_trail_number:C
	  origin_y:V origin_x:V number_of_deltas:v ) ], undef,
     NO_CACHE,
        [ qw( origin_y:V origin_x:V ) ],
        undef );

  *set_plot_trail_deltas           = _make_method( 0x0315, [
        ( qw( plot_trail_number:C number_of_deltas:v ),
          (map { ("delta_y_$_:v", "delta_x_$_:v",) } (1..MAX_DELTAS) ) )
  ], undef,
     NO_CACHE,
        [ (map { ("delta_y_$_:v", "delta_x_$_:v",) } (1..MAX_DELTAS) ) ],
        undef );

}

sub read_memory {
  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  my %input = @_;

  my $callback = $input{callback} || sub { return; };
  assert( ref($callback) eq "CODE" ), if DEBUG;

  my $expected = $input{count}    || 0;

  my $count     = $expected;
  my $data      = "";

  while ($count) {
    &{$callback}( length($data) . "/" . $expected );

    $input{count}    = ($count > MAX_BYTES) ? MAX_BYTES : $count;
    $count          -= $input{count};

    my $buff         = $self->read_memory_location( %input );

    if (length($buff) != $input{count}) {
      die "Unable to read memory"; }

    $data           .= $buff;
    $input{address} += $input{count};
  }

  &{$callback}( length($data) . "/" . $expected );
  return $data;
}

sub DESTROY {
  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  $self->disconnect;
}


1;
__END__

sub get_waypoints {
  require GPS::Lowrance::Waypoints;

  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  my %input    = @_;

  my $callback = $input{callback} || sub { return; };
  assert( ref($callback) eq "CODE" ), if DEBUG;

  my $list     = $input{waypoints} || [1..$self->get_num_of_waypoints];
  assert( ref($list) eq "ARRAY" ), if DEBUG;

  my $list_size = scalar @$list;

  my $waypoints  = new GPS::Lowrance::Waypoints( rounding => 0 );

  foreach my $num (@$list) {

    if ($num > $self->get_num_of_waypoints) {
      die "invalid waypoint number ``$num\'\'";
    }

    &{$callback}( $waypoints->size . "/" . $list_size );

    my $wpt = $self->get_a_waypoint( waypoint_number => $num-1 );

    if ($wpt->{status}) {
      # We eval it, and if the data is invalid, we don't add it.
      eval {
	$waypoints->add_point(
           mercator_meters_to_degrees( $wpt->{latitude}, $wpt->{longitude} ),
           $wpt->{name},
           gps_to_unix_time( $wpt->{date} ),
           $num-1,
           $wpt->{icon_symbol} );
      };
    }
  }

  &{$callback}( $waypoints->size . "/" . $list_size );

  return $waypoints;
}

sub set_waypoints {
  require GPS::Lowrance::Waypoints;

  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  my %input    = @_;

  my $callback = $input{callback} || sub { return; };
  assert( ref($callback) eq "CODE" ), if DEBUG;

  my $waypoints = $input{waypoints};
  assert( UNIVERSAL::isa( $waypoints, "GPS::Lowrance::Waypoints" ) ), if DEBUG;

  my $ignore    = $input{ignore_waypoint_numbers};

  if ($waypoints->size > $self->get_num_of_waypoints) {
    die "waypoints too large";
  }

  $waypoints->reset;

  my $num = 1;
  while (my $wpt = $waypoints->next) {

    &{$callback}( $num . '/' . $waypoints->size );

    my ($lat_m, $lon_m) = degrees_to_mercator_meters( $wpt->[0], $wpt->[1] );
      
    my $wpt_num = $wpt->[4];
    unless (!$ignore || (defined $wpt_num)) { $wpt_num = $num-1; }

    $self->set_a_waypoint(
      waypoint_number => $wpt_num,
      latitude        => $lat_m,
      longitude       => $lon_m,
      name            => $wpt->[2],
      date            => unix_to_gps_time($wpt->[3]),
      status          => 1,
      icon_symbol     => $wpt->[5]||0,
    );

    $num++;
  }

  &{$callback}( $num . '/' . $waypoints->size );

  return;
}


sub set_plot_trail_mercator_meters {
  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  if ($self->get_protocol_version < 1) {
    die "this method requires protocol version 2.0";
  }

  my %input    = @_;
  my $callback = $input{callback} || sub { return; };
  assert( ref($callback) eq "CODE" ), if DEBUG;

  my $trail    = $input{plot_trail};
  assert( ref($trail) eq "ARRAY" ), if DEBUG;

  if ($self->get_num_of_plot_trails < $input{plot_trail_number}) {
    die "plot_trail_number too high";
  } elsif ($input{plot_trail_number} < 0) {
    die "invalid trail number";
  }

  my $count = scalar( @$trail );

  unless ($count) {
    die "cannot upload an empty trail";
  }


  my $point = shift @$trail;
  assert( defined $point ), if DEBUG;

  my ($lat_m, $lon_m) = @$point;

  my %args = (
    plot_trail_number => $trail->trail_num()-1,
    origin_x          => $lon_m,
    origin_y          => $lat_m,
    number_of_deltas  => --$count,
  );

  $self->set_plot_trail_origin( %args );

  # Parse::Binary::FixedFormat will complain if they are not defined

  foreach my $delta (1..40) {
    $args{"delta_x_$delta"} = 0;
    $args{"delta_y_$delta"} = 0;
  }

  while ($count) {
    &{$callback}( ($trail->size - $count) . "/" . $trail->size );

    my $expected = ($count > MAX_DELTAS) ? MAX_DELTAS : $count;

    $args{number_of_deltas} = $expected;
 
    $count -= $expected;
    
    my $delta = 1;
    while ($expected--) {
      $point = shift @$trail;
      assert( defined $point ), if DEBUG;

      my ($y, $x) = @$point;
      my $dy = $y - $lat_m;
      my $dx = $x - $lon_m;

      $args{"delta_x_$delta"} = $dx;
      $args{"delta_y_$delta"} = $dy;

      ($lat_m, $lon_m) = ($y, $x);

      $delta++;
    }
    $self->set_plot_trail_deltas( %args );
  }
  &{$callback}( ($trail->size - $count) . "/" . $trail->size );

  return;
}

sub set_plot_trail {
  require GPS::Lowrance::Trail;

  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  if ($self->get_protocol_version < 1) {
    die "this method requires protocol version 2.0";
  }

  my %input    = @_;

  my $trail    = $input{plot_trail};
  assert( UNIVERSAL::isa( $trail, "GPS::Lowrance::Trail" ) ), if DEBUG;

  $input{plot_trail_number} = $trail->trail_num - 1;

  my @raw_trail = ();

  $trail->reset;
  while (my $point = $trail->next) {
    push @raw_trail, [ mercator_meters_to_degrees( @{$point}[0..1] ) ];
  }
  assert( scalar(@raw_trail) == $trail->size ), if DEBUG;

  $input{plot_trail} = \@raw_trail;

  return $self->set_plot_trail_mercator_meters( %input );
}

sub get_plot_trail_mercator_meters {
  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  if ($self->get_protocol_version < 1) {
    die "this method requires protocol version 2.0";
  }

  my %input    = @_;

  if ($self->get_num_of_plot_trails <= $input{plot_trail_number}) {
    die "plot_trail_number too high";
  }

  my $callback = $input{callback} || sub { return; };
  assert( ref($callback) eq "CODE" ), if DEBUG;

  my $origin   = $self->get_plot_trail_origin( %input );

  my ($origin_x, $origin_y, $delta_count) =
    map { ( ( $origin->{$_} ) ) } (
     qw( origin_x origin_y number_of_deltas ) );

  my @trail = ( [ $origin_y, $origin_x ] );

  my $expected = $delta_count+1;

  while ($delta_count) {

    &{$callback}( scalar(@trail) . "/" . $expected );

    # LSI protocol says that no more than 40 deltas should be
    # downloaded at a time

    $input{number_of_deltas} =
      ($delta_count > MAX_DELTAS) ? MAX_DELTAS : $delta_count;
    $delta_count -= $input{number_of_deltas};

    my $deltas = $self->get_plot_trail_deltas(%input);

    die "unable to retrieve deltas",
      unless ($deltas->{number_of_deltas} == $input{number_of_deltas});

    for my $i (1 .. $input{number_of_deltas}) {
      my ($x, $y) = map { ( ( $deltas->{$_."_$i"}||0) ) } (
        qw( delta_x delta_y ) );
      $origin_x += $x;
      $origin_y += $y;
      push @trail, [ $origin_y, $origin_x ];
    }

  }

  &{$callback}( scalar(@trail) . "/" . $expected );
  return \@trail;
}

sub get_plot_trail {
  require GPS::Lowrance::Trail;

  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  my %input = @_;

  my $raw_trail = $self->get_plot_trail_mercator_meters( %input );

  if (defined $raw_trail) {

    my $trail = new GPS::Lowrance::Trail(
      rounding  => $input{rounding}||0,
      trail_num => $input{plot_trail_number} + 1,
    );
    assert( UNIVERSAL::isa( $trail, "GPS::Lowrance::Trail" ) ), if DEBUG;

    foreach my $pt (@$raw_trail) {
      $trail->add_point( mercator_meters_to_degrees( @{$pt}[0..1] ),
			 @{$pt}[2..-1] );
    }
    assert( $trail->size == scalar(@$raw_trail) ), if DEBUG;

    return $trail;
  } else {
    return;
  }
}

sub get_current_screen {
  require GPS::Lowrance::Screen;

  my $self = shift;
  return GPS::Lowrance::Screen::get_current_screen($self, @_);
}

sub get_graphical_symbol {
  require GPS::Lowrance::Screen;

  my $self = shift;
  return GPS::Lowrance::Screen::get_graphical_symbol($self, @_);
}

=head1 NAME

GPS::Lowrance - Connect to Lowrance and Eagle GPS devices

=head1 REQUIREMENTS

The following modules are required to use this module:

  Carp::Assert
  GPS::Lowrance::LSI 0.23
  Parse::Binary::FixedFormat
  Win32::SerialPort or Device::SerialPort

If you will be using the L</get_plot_trails>, L</set_plot_trails>,
L</set_waypoints> or L</get_waypoints> methods, then you will need the
following modules:

  GPS::Lowrance::Trail 0.41
  Geo::Coordinates::DecimalDegrees
  Geo::Coordinates::UTM
  XML::Generator

If you want to use the screen capture or icon download functions in
C<GPS::Lowrance::Screen>, you also need the following module:

  GD

This module should work with Perl 5.6.x. It has been tested on Perl 5.8.2.

=head1 SYNOPSIS

  use GPS::Lowrance;
  use GPS::Lowrance::Trail;

  $gps = GPS::Lowrance->connect(
            Device     => 'com1',
            BaudRate   => 57600,
          );

  $trail = $gps->get_plot_trail( plot_trail_number => 0 );

  $gps->disconnect;

=head1 DESCRIPTION

This module provides a variety of low- and high-level methods for
communicating with Lowrance and Eagle GPS receivers which support the
LSI 100 protocol.  It also provides some utility functions for
converting data.

This module is a work in progress.

=head2 Methods

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

   0 = Black Pane only
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

=item get_num_of_plot_trails

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

Returns the screen rotation angle (0, 90, 180, or 270).  This can be
used to determine the orientation of screens captures and icons.

The value is based on the original call to L</get_product_information>.

=item get_run_time

  $time = $gps->get_run_time;

Returns the run time of the unit (in seconds).

The value is based on the original call to L</get_product_information>.

=item get_product_description

  $name = $gps->get_product_description

Returns a short description of the product.

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

C<$cart> is either 0, 1 or 2.

=item read_memory

  $data = $gps->read_memory_location(
     address          => $addr,
     count            => $size,
     cartridge_select => $cart,
     callback         => $coderef,     # optional
  );

Reads C<$size> bytes from the memory location in cartridge C<$cart>.

C<$cart> is either 1 or 2.

The C<$coderef> refers to a subroutine that is called for each block
of memory read.  It can be used to display the status (which is passed
to it in the form of a string "total_bytes_read/total_requested").
For example,

  $data = $gps->read_memory_location(
     address          => 123456,
     count            => 2800,
     cartridge_select => 1,
     callback         =>
       sub {
        my $status = shift || "0/0";
        print STDERR $status, "\r";
       },
  );

=item login_to_serial_port

  $hash_ref = $gps->login_to_serial_port;

=item request_screen_pointer

  $hash_ref = $gps->request_screen_pointer;

Freezes the GPS display for downloading and returns pointers.  The GPS will
be locked until there is a call to L</unfreeze_current_unit_screen>.

The C<GPS::Lowrance::Screen> module provides a wrapper routine to extract
the current screen as a C<GD> image.

=item unfreeze_current_unit_screen

  $gps->unfreeze_current_unit_screen;

Called to unlock the GPS display.

=item get_plot_trail_origin

  $hashref = $fps->get_plot_trail_origin(
    plot_trail_numer => $num,
  );

Note that returned values are in mercator meters and must be
converted. (See L<Geo::Coordinates::MercatorMeters> for conversion
routines.)

This only works for devices that understand I<protocol version 2>
(L</get_protocol_version> == 1).

See L</get_plot_trail>, which is a wrapper routine for downloading
plot trails.

=item get_plot_trail_deltas



The protocol specifies that no more than 40 deltas may be requested at
a time.

Note that returned values are in mercator meters and must be
converted. (See L<Geo::Coordinates::MercatorMeters> for conversion
routines.)

This only works for devices that understand I<protocol version 2>
(L</get_protocol_version> == 1).

See L</get_plot_trail>, which is a wrapper routine for downloading
plot trails.

=item get_plot_trail_mercator_meters

  $array_ref = $gps->get_plot_trail_mercator_meters(
     plot_trail_number => $num,
     callback          => $code_ref,
  );

Retrieves the trail specified by C<$num> (which is zero-based) as an
array reference of coordinates in mercator meters:

  $array_ref = [ [ $lat_m_1, $lon_m_1 ], [ $lat_m_2, $lon_m_2 ], ... ];

It uses L</get_plot_trail_origin> and L</get_plot_trail_deltas> to
retrieve plot trails, and convert the data to Latitude and Logitude.
Thus it only works for devices that understand I<protocol version 2>
(L</get_protocol_version> == 1).

=item get_plot_trail

  $trail = $gps->get_plot_trail(
     plot_trail_number => $num,
     callback          => $code_ref,
  );

Retrieves the trail specified by C<$num> (which is zero-based) as a
C<GPS::Lowrance::Trail> object.

Note the following:

  $trail->trail_num == $num+1

Coordinates are converted to decimal degrees from the native mercator
meter format.  Note that there may be rounding errors.

It uses L</get_plot_trail_mercator_meters>.

=item set_plot_trail_origin

  $gps->set_plot_trail_origin(
    plot_trail_number => $num,
    origin_x          => $origin_x,
    origin_y          => $origin_y,
    number_of_deltas  => $num_deltas,
  );

Sets the origin of the plot trail specified by C<$num>.  The plot
origin is specified in mercator meters.

This only works for devices that understand I<protocol version 2>
(L</get_protocol_version> == 1).

See L</set_plot_trail>, which is a wrapper function to handle
uploading trails.

=item set_plot_trail_deltas

  $gps->set_plot_trail_deltas(
    plot_trail_number => $trail_number,
    number_of_deltas  => $num_deltas,
    delta_x_1         => $delta_x_1,
    delta_y_1         => $delta_y_1,
    ...
    delta_x_40        => $delta_x_40,
    delta_y_40        => $delta_y_40,
  );


The protocol specifies that no more than 40 deltas may be uploaded at
a time.

Note that accepted values are in mercator meters and must be
converted. (See L<Geo::Coordinates::MercatorMeters> for conversion
routines.)

This only works for devices that understand I<protocol version 2>
(L</get_protocol_version> == 1).

See L</set_plot_trail>, which is a wrapper function to handle
uploading trails.

=item set_plot_trail_mercator_meters

  $gps->set_plot_trail_mercator_meters(
    plot_trail_number => $num,
    plot_trail => $array_ref,
    callback   => $coderef,
  );

Sets plot trail C<$num> to the one specified by C<$trail>.  C<$trail> is the
same format returned by L</get_plot_trail_mercator_meters>.

It uses L</set_plot_trail_origin> and L</set_plot_trail_deltas> to
upload plot trails, and convert the data from Latitude and Logitude.
Thus it only works for devices that understand I<protocol version 2>
(L</get_protocol_version> == 1).

=item set_plot_trail

  $trail = new GPS::Lowrance::Trail;

  ...

  $gps->set_plot_trail(
    plot_trail => $trail,
    callback   => $coderef,
  );

Sets a plot trail to the one specified by C<$trail>.

It uses L</set_plot_trail_mercator_meters>.

=item get_a_waypoint

  $waypoint = $gps->get_a_waypoint( waypoint_number => $num );

Retrieves a waypoint specified by C<$num> (which is zero-based) as a
hash reference wih the following information:

  waypoint_number
  latitude (in Mercator Meters)
  longitude (in Mercator Meters)
  name (up to 13 characters long)
  status (0 = invalid, 1 = valid)
  date (number of seconds since Jan. 1, 1992)

The L</mercator_meters_to_degrees> and L</gps_to_unix_time> functions
will convert latitude and lognitude and date fields.

For some GPS models, C<name> may be no longer than 8 characters.

=item set_a_waypoint

  $gps->set_a_waypoint( %waypoint );

Sets a waypoint, using the same structure that is returned by
L</get_a_waypoint>.

=item get_waypoints

  $wpts = $gps->get_waypoints(
    waypoints => [1..($gps->get_num_of_waypoints)],
    callback  => $coderef,
  );

Retrieves a set of waypoints.  If no set is specified, it will
retrieve all active waypoints with valid coordinates.

The returned value is a C<GPS::Lowrance::Waypoints> object.  It has
the same methods as C<GPS::Lowrance::Trail>.

Note that the waypoint number and symbol is lost in the output.

=item set_waypoints

  $wpts = new GPS::Lowrance::Waypoints;
  ...

  $gps->set_waypoints(
    waypoints => $wpt,
    callback  => $coderef,
    ignore_waypoint_numbers => $bool,
  );

Uploads waypoints in the unit.

=item get_number_of_graphical_symbols

  $num = $gps->get_number_of_graphical_symbols;

Returns the number of graphical icon symbols in the device.  This is
not necessarily the maximum number of icon symbols that the device can
support. (See L</get_num_of_icon_symbols>.)

=item get_graphical_sumbol

  $info = $gps->get_graphical_symbol(
    icon_symbol_index => $num,
  );

Returns information about the icon symbol:

  width                  = width-1 of the icon
  height                 = height of the icon
  structure_pointer      = memory address where the icon bitmap is
  bytes_per_symbol       = amount of data

See the C<get_graphical_symbol> function in C<GPS::Lowrance::Screen>.

=item get_current_screen

  $img = $gps->get_current_screen(
    black_rgb => [0x00, 0x00, 0x00],
    grey_rgb  => [0x80, 0x80, 0x80],
    callback  => $coderef
  );

Returns a C<GD::Image> object of the current screen on the GPS.

The C<black_rgb> and C<grey_rgb> values are optional.  They specify
the screen colors used.  Default values are shown in the example.

=item get_icon_graphic

  $img = $gps->get_icon_graphic(
    icon_symbol_index => $icon_num,
    black_rgb => [0x00, 0x00, 0x00],
    grey_rgb  => [0x80, 0x80, 0x80],
    callback  => $coderef
  );

Returns a C<GD::Image> object of the icon specified by
C<icon_symbol_index>.  

=item disconnect

  $gps->disconnect;

Disconnects the serial connection.

=back

=head2 Functions

The following functions are exported by default:

=over

=item gps_to_unix_time

  my $time = gps_to_unix_time( $waypoint->{date} );

Converts a GPS date (such as from a waypoint) to a Unix date.

=item unix_to_gps_time

  $waypoint->{date} = unix_to_gps_time( time )

Converts Unix date to a GPS date.

=item mercator_meters_to_degrees

  ($lat, $lon) = mercator_meters_to_degrees( $lat_m, $lon_m );

Convert mercator meters to decimal degrees.  This function is
imported from L<Geo::Coordinates::MercatorMeters>.

=item degrees_to_mercator_meters

  ($lat_m, $lon_m) = degrees_to_mercator_meters( $lat, $lon );

Convert decimal degrees to mercator meters.  This function is
imported from L<Geo::Coordinates::MercatorMeters>.

=item signed_long

  $lat = signed_long( $lat );

Convert an unsigned long to a signed long.

=item signed_int

  $delta = signed_int( $delta );

Convert an unsigned int to a signed int.

=back

=head1 CAVEATS

This is a beta version of the module, so there are bound to be some bugs.
In the current form it is also far from complete.

This module was tested with C<Win32::SerialPort>, although it should
use C<Device::SerialPort> on non-Windows platforms.  However, this has
not yet been tested.

=head2 Known Issues

The LSI-100 protocol uses mercator meters for coordinates, whereas
these functions (and most mapping software) use degrees.  Because of
this, there will be rounding errors in converting between the formats.
This means that data (e.g. trails and waypoints) which are repeatedly
downloaded and uploaded will become increasingly inaccurate.

The protocol uses little-endian values, and due to some quirks in the
decoding functions, they may not be converted properly on big-endian
machines.

=head2 Compatability

This module should work with all Lowrance and Eagle devices which
support the LSI 100 protocol.  It has been tested on the following
model(s):

=over

=item Lowrance GlobalMap 100 (same as Eagle MapGuide Pro?)

=back

If you have tested it on other models, please notify me.

=head2 Unsupported Functions

Because devices vary, there is no way to ensure that every device will
work with every function.

GPS units may not respond if they do not support or understand a
specific command.  In most cases the functions will time out and
return C<undef> after several retries.

=head1 SEE ALSO

The Lowrance Serial Interface (LSI) 100 Protocol is described in a
document available on the Lowrance or Eagle web sites:

  http://www.lowrance.com/Software/CyberCom_LSI100/cybercom_lsi100.asp

  http://www.eaglegps.com/Downloads/Software/CyberCom/default.htm

A low-level implementation is available in

  GPS::Lowrance::LSI

This module does not support the NMEA protocol. For one that does, see

  GPS::NMEA

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
