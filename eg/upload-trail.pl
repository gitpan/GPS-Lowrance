# Example file to extract trails from Lowrance or Eagle GPS
# Copyright (C) 2004 Robert Rothenberg <rrwo at cpan.org>

use strict;

use FileHandle;
use Getopt::Long;
use GPS::Lowrance 0.21;
use GPS::Lowrance::Trail 0.40;

our $VERSION = '0.01';

my %ALLOWED_FORMATS = (
  'gdm16'  => 'read_gdm16',
  'latlon' => 'read_latlon',
  'utm'    => 'read_utm',
);

my ($Device, $BaudRate, $Filename, $TrailNo, $Format, $Quiet, $Help);

GetOptions(
  'device=s'   => \$Device,
  'baudrate=i' => \$BaudRate,
  'trail=i'    => \$TrailNo,
  'filename=s' => \$Filename,
  'format=s'   => \$Format,
  'quiet|q!'   => \$Quiet,
  'help|h!'    => \$Help,
);

if ($Help) {
  print STDERR << "HELP";
Usage: $0 --device=device --baudrate=baud --trail=trail]
         [--format=latlon|utm|gdm16] [--filename=filename]
         [--quiet] [--help]
Upload trails to Lowrance or Eagle GPS.
 Version: $VERSION
 Example:
  $0 --device=com1 --baudrate=57600 --trail=1 --filename=trail.txt
 Options:
  --device   Name of the serial device that the GPS is plugged in to
  --baudrate Baud rate
  --trail    Trail Number (between 1 and 4, depending on GPS unit)
  --format   Trail format (latlon|gdm16|utm|gpx) latlon is default
  --filename Name of file to import to (STDIN if not specified)
  --quiet    Turn off status
  --help     Display this screen
HELP
  exit -1;
}

my $Fh = \*STDIN;
if (defined $Filename) {
  $Fh = new FileHandle "$Filename";
  unless (defined $Fh) {
    die "Unable to open file ``$Filename\'\'\n";
  }
}

$Format ||= 'latlon';
unless (exists $ALLOWED_FORMATS{ $Format }) {
  die "Invalid format ``$Format\'\'";
}
my $ReadMethod = $ALLOWED_FORMATS{ $Format };

my $Gps = GPS::Lowrance->connect(
  'device'   => $Device,
  'baudrate' => $BaudRate,
) or die "Unable to connect to GPS";

unless ($Quiet) {
  print STDERR "Connected to ", $Gps->get_product_description, "\n";
}

# The method used by this device requires protocol version 2.0

if ($Gps->get_protocol_version < 1) {
  die "Device does not support plot trail uploads\n";
}

if (($TrailNo<1) || ($TrailNo>$Gps->get_num_of_plot_trails)) {
   die "Invalid plot trail number ``$TrailNo\'\'\n";
}

sub status {
  unless ($Quiet) {
    my $stat = shift;
    print STDERR "Uploaded $stat\r";
  }
}

my $Trail = new GPS::Lowrance::Trail;

$Trail->$ReadMethod( $Fh );

$Trail->trail_num($TrailNo);

$Gps->set_plot_trail(
   plot_trail        => $Trail,
   callback          => \&status,
);

unless ($Quiet) {
  print STDERR "\n";
}

$Gps->disconnect;

if (defined $Filename) {
  $Fh->close;
}

exit;
