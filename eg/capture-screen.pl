# Example file to capture screen from Lowrance or Eagle GPS
# Copyright (C) 2004 Robert Rothenberg <rrwo at cpan.org>

use strict;

use GD;
use FileHandle;
use Getopt::Long;
use GPS::Lowrance 0.10;
use GPS::Lowrance::Screen 0.03;

our $VERSION = '0.03';

my %ALLOWED_FORMATS = (
  'png'    => 'png',
);

my ($Device, $BaudRate, $Filename, $TrailNo, $Format, $Quiet, $Help);

GetOptions(
  'device=s'   => \$Device,
  'baudrate=i' => \$BaudRate,
  'filename=s' => \$Filename,
  'format=s'   => \$Format,
  'quiet|q!'   => \$Quiet,
  'help|h!'    => \$Help,
);

if ($Help) {
  print STDERR << "HELP";
Usage: $0 --device=device --baudrate=baud --trail=trail]
         [--format=png] [--filename=filename]
         [--quiet] [--help]
Extract screen from Lowrance or Eagle GPS.
 Version: $VERSION
 Example:
  $0 --device=com1 --baudrate=57600
 Options:
  --device   Name of the serial device that the GPS is plugged in to
  --baudrate Baud rate
  --format   File format (png is default)
  --filename Name of file to extract to (STDOUT if not specified)
  --quiet    Turn off status
  --help     Display this screen
HELP
  exit -1;
}

my $Fh = \*STDOUT;
if (defined $Filename) {
  $Fh = new FileHandle ">$Filename";
  unless (defined $Fh) {
    die "Unable to create file ``$Filename\'\'\n";
  }
}

$Format ||= 'png';
unless (exists $ALLOWED_FORMATS{ $Format }) {
  die "Invalid format ``$Format\'\'";
}
my $WriteMethod = $ALLOWED_FORMATS{ $Format };

my $Gps = GPS::Lowrance->connect(
  'device'   => $Device,
  'baudrate' => $BaudRate,
) or die "Unable to connect to GPS";

unless ($Quiet) {
  print STDERR "Connected to ", $Gps->get_product_description, "\n";
}

sub status {
  unless ($Quiet) {
    my $stat = shift;
    print STDERR "Downloaded $stat\r";
  }
}

my $Img = get_current_screen( $Gps, callback => \&status, );

unless ($Quiet) {
  print STDERR "\n";
}

binmode $Fh;

print $Fh $Img->$WriteMethod;

$Gps->disconnect;

if (defined $Filename) {
  $Fh->close;
}

exit;
