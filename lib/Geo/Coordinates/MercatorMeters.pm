package Geo::Coordinates::MercatorMeters;

use 5.006;
use strict;
use warnings;

require Exporter;
# use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(
  mercator_meters_to_degrees degrees_to_mercator_meters
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw(
  mercator_meters_to_degrees degrees_to_mercator_meters
);

our $VERSION = '0.02';

use POSIX qw( atan exp tan );

use Carp::Assert;

use constant DEG_TO_RAD => 0.017453292519943296;
use constant RAD_TO_DEG => 57.295779513082322;
use constant PI         => 3.14159267;
use constant MAGIC_NUM  => 6356752.3142;

sub mercator_meters_to_degrees {
  no integer;
  my ($lat_m, $lon_m) = @_;
  my $lat = RAD_TO_DEG * ( (2 * atan( exp( $lat_m / MAGIC_NUM ) ) ) - (PI/2) );
  my $lon = RAD_TO_DEG * ($lon_m / MAGIC_NUM);

  assert( ($lat>=-90) && ($lat<=90) ), if DEBUG;
  assert( ($lon>=-90) && ($lon<=90) ), if DEBUG;

  return ($lat, $lon);
}

sub degrees_to_mercator_meters {
  no integer;
  my ($lat, $lon) = @_;

  assert( ($lat>=-90) && ($lat<=90) ), if DEBUG;
  assert( ($lon>=-90) && ($lon<=90) ), if DEBUG;

  my $lat_m = MAGIC_NUM * log( tan( (($lat * DEG_TO_RAD) + (PI/2)) / 2 ) );
  my $lon_m = MAGIC_NUM * ($lon *DEG_TO_RAD);
  return ($lat_m, $lon_m);
}


1;
__END__


=head1 NAME

Geo::Coordinates::MercatorMeters - Convert between mercator meters and degrees

=head1 SYNOPSIS

  use Geo::Coordinates::MercatorMeters;

  ($lat_m, $lon_m) = degrees_to_mercator_meters( $lat, $lon );

  ($lat,   $lon)   = mercator_meters_to_degrees( $lat_m, $lon_m );

=head1 DESCRIPTION

These are utility functions for conversions between decimal degrees
and mercator meters latitude and longitude.

=head1 SEE ALSO

These formulas are required for conversions to use the Lowrance Serial
Interface Protocol in the C<GPS::Lowrance> module.

These functions and the Lowrance Serial Interface (LSI) Protocol is
described in a document available on the Lowrance
(L<http://www.lowrance.com>) or Eagle (L<http://www.eaglegps.com>)
web sites.

For other coordinate conversions, see these modules:

  Geo::Coordinates::DecimalDegrees

  Geo::Coordinates::UTM

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
