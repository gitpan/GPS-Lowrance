package GPS::Lowrance::Screen;

use 5.006;
use strict;
use warnings;

use Carp::Assert;
use GD;
use GPS::Lowrance 0.02;

require Exporter;
# use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(
  get_current_screen
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw(
  get_current_screen
);

our $VERSION = '0.01';

sub get_current_screen {
  my $gps = shift;
  assert( UNIVERSAL::isa( $gps, "GPS::Lowrance" ) ), if DEBUG;

  my $callback = shift || sub { return; };
  assert( ref($callback) eq "CODE" ), if DEBUG;

  my $blk_rgb = shift || [0,   0,   0  ];
  my $gry_rgb = shift || [128, 128, 128];

  my $info = $gps->request_screen_pointer;

  # Has been tested with screen type 1, but not others

  my $width  = $gps->get_screen_width()  + 1;
  my $height = $gps->get_screen_height() + 1;

  if ( ($gps->get_screen_rotate_angle == 90) ||
       ($gps->get_screen_rotate_angle == 270) ) {
    ($width, $height) = ($height, $width);
  }

  my $img = new GD::Image( $width, $height );

  # It's tempting to use Graphics::ColorNames for "black" and "grey", but
  # to load a module for just two colors seems pointless.

  my $blk = $img->colorAllocate( @$blk_rgb );
  my $gry = $img->colorAllocate( @$gry_rgb );

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

  # If we were returning a monochrome Windows Bitmap, we could probably
  # copy that data as-is.

  my ($x, $y) = (0, 0);
  foreach my $byte (split //, $blk_plane) {
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

GPS::Lowrance::Screen - capture screen from GPS device

=head1 SYNOPSIS

  use GD;

  use GPS::Lowrance;
  use GPS::Lowrance::Screen;

  $gps = GPS::Lowrance->connect( ... );

  $img = get_current_screen( $gps );

=head1 REQUIREMENTS

The following modules are required to use this module:

  Carp::Assert
  GPS::Lowrance

This module should work with Perl 5.6.x. It has been tested on Perl 5.8.2.

=head2 Installation

It is included with the C<GPS::Lowrance> distribution.

=head1 DESCRIPTION

Captures the current screen on a Lowrance or Eagle GPS.

This has been made a separate module so that one is not required to
have graphics modules installed in order to use the main
L<GPS::Lowrance> module.

=head2 Functions

=over

=item get_current_screen

  $img = get_current_screen( $gps, $callback, $rgb_ref, $rgb_ref );

Returns a C<GD::Image> object of the current screen on the GPS.

The C<$callback> refers to a subroutine which handles the status. See
L<GPS::Lowrance> documentation for more information about callbacks.

You can also specify the RGB values to use instead of black and
grey. If you prefer black on white, use:

  $img = get_current_screen( $gps, undef, [0,0,0], [255,255,255] );
  
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
