package GPS::Lowrance::Waypoints;

use 5.006;
use strict;
use warnings;

use Carp::Assert;
use GPS::Lowrance::Trail 0.40;
use XML::Generator;

# require Exporter;
# use AutoLoader qw(AUTOLOAD);

our @ISA = qw(GPS::Lowrance::Trail);

# our %EXPORT_TAGS = ( 'all' => [ qw(
# ) ] );

# our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
# our @EXPORT = qw(
# );

our $VERSION = '0.02';

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);
  $self->{WPT_INDEX} = { };             # waypoint numbers
  return $self;
}

sub add_point {
  my $self = shift;
  assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

  my ($latitude, $longitude, $name, $date, $symbol, $number) = @_;

  assert( ($latitude  >= -90) && ($latitude  <= 90) ), if DEBUG;
  assert( ($longitude >= -90) && ($longitude <= 90) ), if DEBUG;

  $name ||= ""; 
  if ($name) {
    $name =~ /^\"?(.*)\"?$/; $name = $1;
  }

  $symbol ||= 0;

  unless ($number) { $number = $self->size; }
  if (defined $self->{WPT_INDEX}->{$number}) {
    die "waypoint number ``$number\'\' already defined";
  } else {
    $self->{WPT_INDEX}->{$number} = $self->size;
  }

  push @{ $self->{POINTS} },
    [ $latitude, $longitude, $name, $date, $number, $symbol ];
  ++$self->{COUNT};
}

sub trail_num {
  return 0;
}

sub write_gpx {
    my $self = shift;
    assert( UNIVERSAL::isa( $self, __PACKAGE__ ) ), if DEBUG;

    my $xml  = new XML::Generator(
      pretty=>2,
    );

    my $fh   = shift;
    unless (defined $fh) { $fh = \*STDOUT; }

    my @gpx = ();

    $self->reset;
    while (my $point = $self->next) {
      my $trkpt = [ {
        lat => $point->[0],
        lon => $point->[1],
      }, undef ] ;
      if (($point->[2]||"") ne "") {
	push @$trkpt, $xml->name($point->[2]);
      }
      if (defined $point->[3]) {
	my ($sec, $min, $hour, $mday, $mon, $year) = gmtime($point->[3]);
	my $time = sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ',
         $year+1900, $mon+1, $mday, $hour, $min, $sec);
	push @$trkpt, $xml->time($time);
      }
      push @gpx, $xml->wpt( @$trkpt );
    }

    print $fh '<?xml version="1.0"?>', "\n";
    print $fh $xml->gpx( { version => '1.0',
                 creator => __PACKAGE__ . " $VERSION" },
	      @gpx );

}

1;
__END__

=head1 NAME

GPS::Lowrance::Waypoints - support for waypoints

=head1 SYNOPSIS

  use GPS::Lowrance::Waypoints;

  $wpts = new GPS::Lowrance::Waypoints;
  ...
  $wpts->write_gpx( $fh );

=head1 REQUIREMENTS

The following modules are required to use this module:

  Carp::Assert
  GPS::Lowrance::Trail
  XML::Generator

This module should work with Perl 5.6.x. It has been tested on Perl 5.8.2.

=head2 Installation

It is included with the C<GPS::Lowrance> distribution.

=head1 DESCRIPTION

This module is a subclass of C<GPS::Lowrance::Trail>.  It shares the same
methods with exceptions outlined below.

=head2 Methods

=over

=item add_point

  $wpt->add_point( $lat, $lon, $name, $date, $sym_num, $wpt_num );

Add a new waypoint.

=item trail_num

This method always returns 0.

=item write_gpx

  $wpt->write_gpx( $fh );

This function writes a GPX file containing waypoints instead of tracks.

=back

=head1 SEE ALSO

  GPS::Lowrance::Trail

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
