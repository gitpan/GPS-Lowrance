package GPS::Lowrance::Screen;

use 5.006;
use strict;
use warnings;

use Carp::Assert;
use GD;
use GPS::Lowrance 0.21;

require Exporter;
# use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(
  get_current_screen get_graphical_symbol
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw(
  get_current_screen get_graphical_symbol
);

our $VERSION = '0.03';

sub get_current_screen {
  my $gps = shift;
  assert( UNIVERSAL::isa( $gps, "GPS::Lowrance" ) ), if DEBUG;

  my %input    = @_;

  my $callback = $input{callback} || sub { return; };
  assert( ref($callback) eq "CODE" ), if DEBUG;

  my $blk_rgb  = $input{black_rgb} || [0,   0,   0  ];
  my $gry_rgb  = $input{grey_rgb}  || [128, 128, 128];

  my $info = $gps->request_screen_pointer;

  # Has been tested with screen type 1, but not others

  my $width  = $gps->get_screen_width()  + 1;
  my $height = $gps->get_screen_height() + 1;

  if ( ($gps->get_screen_rotate_angle == 90) ||
       ($gps->get_screen_rotate_angle == 270) ) {
    ($width, $height) = ($height, $width);
  }

  assert( ($width % 8) == 0 ), if DEBUG; # should be a multiple of 8

  my $size = ($width / 8) * $height;

  assert( $size <= $info->{black_count} ), if DEBUG;

  my $blk_plane = $gps->read_memory(
     address          => $info->{black_address},
     count            => $size,
     cartridge_select => 1,
     callback         => $callback,
  );

  $gps->unfreeze_current_unit_screen;

  my $img = _bitmap_to_image($blk_plane, $width, $height, $blk_rgb, $gry_rgb);

  if ($gps->get_screen_rotate_angle == 90 ) {
    return $img->copyRotate270();
  } elsif ($gps->get_screen_rotate_angle == 180 ) {
    return $img->copyRotate180();
  } elsif ($gps->get_screen_rotate_angle == 270 ) {
    return $img->copyRotate90();
  } else {
    return $img;
  }
}


sub _bitmap_to_image {
  my ($data, $width, $height, $blk_rgb, $gry_rgb) = @_;
  
  my $img = new GD::Image( $width, $height );

  # It's tempting to use Graphics::ColorNames for "black" and "grey", but
  # to load a module for just two colors seems pointless.

  my $blk = $img->colorAllocate( @$blk_rgb );
  my $gry = $img->colorAllocate( @$gry_rgb );

  my ($x, $y) = (0, 0);
  foreach my $byte (split //, $data) {
    my $i   = unpack "C", $byte;
    my $bit = 128;
    while ($bit) {
      my $on = ($i & $bit);
      $img->setPixel( $x, $y, ($on)?$blk:$gry );
      $bit = $bit >> 1;
      $x ++;
      if ($x==$width) {
	$x = 0;
	$y ++;
	assert( $y <= $height ), if DEBUG;
      }
    }
  }
  return $img;
}

sub get_graphical_symbol {
  my $gps = shift;
  assert( UNIVERSAL::isa( $gps, "GPS::Lowrance" ) ), if DEBUG;

  my %input    = @_;

  my $callback = $input{callback} || sub { return; };
  assert( ref($callback) eq "CODE" ), if DEBUG;

  my $blk_rgb  = $input{black_rgb} || [0,   0,   0  ];
  my $gry_rgb  = $input{grey_rgb}  || [128, 128, 128];

  my $sym_num  = $input{icon_symbol_index} || 0;
  unless( ($sym_num >= 0) &&
	  ($sym_num < $gps->get_number_of_graphical_symbols) ) {
    die "Invalid icon number: ``$sym_num\'\'";
  }

  my $info = $gps->get_graphical_symbol_info( icon_symbol_index => $sym_num, );

  assert( $info->{icon_symbol_index} == $sym_num ), if DEBUG;

  my $width  = $info->{width} + 1;
  my $height = $info->{height};

  assert( ($width % 8) == 0 ), if DEBUG; # should be a multiple of 8

  my $size = $info->{bytes_per_symbol};

  my $icon = $gps->read_memory(
     address          => $info->{structure_pointer},
     count            => $size,
     cartridge_select => 0,
     callback         => $callback,
  );


  my $img = _bitmap_to_image($icon, $width, $height, $blk_rgb, $gry_rgb);

  if ($gps->get_screen_rotate_angle == 90 ) {
    return $img->copyRotate270();
  } elsif ($gps->get_screen_rotate_angle == 180 ) {
    return $img->copyRotate180();
  } elsif ($gps->get_screen_rotate_angle == 270 ) {
    return $img->copyRotate90();
  } else {
    return $img;
  }
}

1;
__END__

=head1 NAME

GPS::Lowrance::Screen - capture screen or icons from GPS device

=head1 SYNOPSIS

  use GD;

  use GPS::Lowrance;
  use GPS::Lowrance::Screen;

  $gps = GPS::Lowrance->connect( ... );

  $img = get_current_screen( $gps );

=head1 REQUIREMENTS

The following modules are required to use this module:

  Carp::Assert
  GD
  GPS::Lowrance

This module should work with Perl 5.6.x. It has been tested on Perl 5.8.2.

=head2 Installation

It is included with the C<GPS::Lowrance> distribution.

=head1 DESCRIPTION

Captures the current screen or icons on a Lowrance or Eagle GPS.

This has been made a separate module so that one is not required to
have graphics modules installed in order to use the main
L<GPS::Lowrance> module.

=head2 Functions

=over

=item get_current_screen

  $img = get_current_screen( $gps,
    black_rgb => [0x00, 0x00, 0x00],
    grey_rgb  => [0x80, 0x80, 0x80],
    callback  => $coderef
  );

Returns a C<GD::Image> object of the current screen on the GPS.

The C<$callback> refers to a subroutine which handles the status. See
L<GPS::Lowrance> documentation for more information about callbacks.

The C<black_rgb> and C<grey_rgb> values are optional.

=item get_icon_graphic

  $img = get_icon_graphic( $gps,
    icon_symbol_index => $icon_num,
    black_rgb => [0x00, 0x00, 0x00],
    grey_rgb  => [0x80, 0x80, 0x80],
    callback  => $coderef
  );


Returns a C<GD::Image> object of the icon specified by
C<icon_symbol_index>.  

=back

=head1 CAVEATS

This may not work on all GPS models.

This has only been tested with units having a
L<GPS::Lowrance/get_screen_type|screen type> of 1.  It may not work
for other screen types.

=head1 SEE ALSO

  GPS::Lowrance

If you want to refer to colors by name, see L<Graphics::ColorNames>.

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
