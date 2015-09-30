#!/usr/bin/perl -w

use strict;
use warnings;
use utf8;
use Getopt::Long;
use open qw(:std :utf8);

my $dir_check = 1;
my $show_help = 0;
my $verbose = 0;
my $base_dir = "";
my $sox_command = "";

# most basic use:  audio data only (defaults to col 0)
my $col_snd = 0;

# utt and speaker id default to $col_snd
my $col_rec = -1;
my $col_utt = -1;
my $col_spk = -1;

# optional info:  segmentation, transcription
my $col_chan = -1;
my $col_seg_s = -1;
my $col_seg_e = -1; # defaults to $col_seg_s + 1
my $col_trl = -1;

GetOptions(
	'help' => \$show_help,
	'verbose' => \$verbose,
	'sox-command=s' => \$sox_command,
	'base-dir=s' => \$base_dir,
	'col-snd=i' => \$col_snd,
	'col-rec=i' => \$col_rec,
	'col-utt=i' => \$col_utt,
	'col-spk=i' => \$col_spk,
	'col-beg=i' => \$col_seg_s,
	'col-end=i' => \$col_seg_e,
	'col-trl=i' => \$col_trl,
	'dir-check!' => \$dir_check
);

if ($show_help or scalar @ARGV != 2) {
	printf STDERR "Generate a s5-style data directory based on a file list with\n";
	printf STDERR "optional speaker id and transcripts.\n";
	printf STDERR "Usage:  $0 [options] list out-dir\n";
	printf STDERR "Options:\n";
	printf STDERR "  --verbose       Output verbose logging\n";
	printf STDERR "  --base-dir=dir  List to be relative to 'dir'\n";
	printf STDERR "  --sox-command='...'  Write pipe instead of files use (file) as variable, e.g.\n";
	printf STDERR "  --sox-command='sox -t raw -r 44100 -e a-law (file) -t wav -r 8000 -e signed -c 1 - |'\n";
	printf STDERR "  --col-snd=i     Expect snd file in field col i (default = $col_snd)\n";
	printf STDERR "  --col-rec=i     Expect rec name in field col i (default = \$col_snd)\n";
	printf STDERR "  --col-utt=i     Expect utterance id in field col j (default = \$col_snd\n";
	printf STDERR "  --col-spk=i     Expect speaker id in field k (default = \$col_snd\n";
	printf STDERR "  --col-beg=i     Expect segment begin time in field k\n";
	printf STDERR "  --col-beg=i     Expect segment end time in field k\n";
	printf STDERR "  --col-trl=i     Expect transcripts to start in field i\n";

	exit 1;
}

my ($listf, $dir) = @ARGV;

if (-d "$dir" and $dir_check) {
	printf STDERR "Directory $dir already exists.  Aborting.\n";
	exit 1;
}

if (length $sox_command > 0 and not $sox_command =~ /|$/) {
	printf STDERR "Invalid sox command '$sox_command': must end on pipe operator\n";
	exit 1;
}

# set defaults for rec, utt and spk column
if ($col_snd >= 0) {
	$col_rec = $col_snd if ($col_rec < 0);
}

$col_utt = $col_rec if ($col_utt < 0);
$col_spk = $col_rec if ($col_spk < 0);

# set default for 
if ($col_seg_s >= 0) {
	$col_seg_e = $col_seg_s + 1 if ($col_seg_e < 0);
}

# expect trl, verify that offset is max among indices
if ($col_trl >= 0) {
	$col_trl > $col_snd or die "Invalid --col-trl (must me max among indices)\n";
	$col_trl > $col_rec or die "Invalid --col-trl (must me max among indices)\n";
	$col_trl > $col_utt or die "Invalid --col-trl (must me max among indices)\n";
	$col_trl > $col_spk or die "Invalid --col-trl (must me max among indices)\n";
	$col_trl > $col_seg_s or die "Invalid --col-trl (must me max among indices)\n";
	$col_trl > $col_seg_e or die "Invalid --col-trl (must me max among indices)\n";
	$col_trl > $col_chan or die "Invalid --col-trl (must me max among indices)\n";
}

if (length $base_dir > 0) {
	$base_dir =~ s/\/$//;
}

if ($verbose) {
	printf STDERR "Writing audio info to $dir/wav.scp\n";

	printf STDERR "Expecting sound file at col $col_snd\n";
	printf STDERR "Expecting recording-id at col $col_rec\n";
	printf STDERR "Expecting utterance-id at col $col_utt\n";
	printf STDERR "Expecting speaker-id at col $col_spk\n";
	printf STDERR "Expecting segmentation at cols $col_seg_s,$col_seg_e\n" if $col_seg_s >= 0;
	printf STDERR "Expecting transcription at cols $col_trl-\n" if $col_trl > 0;
	printf STDERR "Expecting channel at col $col_chan\n" if $col_chan >= 0;
	printf STDERR "Using sox pipe: $sox_command\n" if length $sox_command > 0;
	printf STDERR "Prepending base dir: $base_dir\n" if length $base_dir > 0;
}

# shortcuts for later
my $has_transcription = $col_trl > 0;
my $has_segmentation = $col_seg_s > 0;
my $has_channel = $col_chan >= 0;

# find minimum number of columns
my $min_cols;
if ($has_transcription) {
	$min_cols = $col_trl; # we might have empty transcriptions
} else {
	$min_cols = $col_snd;
	$min_cols = $col_rec if $col_rec > $min_cols;
	$min_cols = $col_utt if $col_utt > $min_cols;
	$min_cols = $col_spk if $col_spk > $min_cols;
	$min_cols = $col_seg_s if $col_seg_s > $min_cols;
	$min_cols = $col_seg_e if $col_seg_e > $min_cols;
	$min_cols = $col_chan if $col_chan > $min_cols;
}

# basic info
my %hwav = ();
my %hwavc = ();
my %hspk = ();
my %htext = ();

# segments info
my @aseg = ();

# read in table
open (FI, "<$listf") or die "Could not open $listf for reading.\n";
my $ln = 0;
while (<FI>) {
	$ln += 1;

	my @l = split /\s+/;

	if ((scalar @l) < int($min_cols)) {
		printf STDERR "$listf:%d  not enough columns (%d:%d);  line is: $_\n", $ln, scalar @l, $min_cols;
		next;
	}

	# defaults for segment info
	my $chan = "A";
	my $s = 0;
	my $e = -1;

	my $snd = $l[$col_snd];
	$snd = $base_dir."/".$snd if (length $base_dir > 0);
	my $rec = $l[$col_rec];
	my $utt = $l[$col_utt];

	my $spk = $l[$col_spk];
	$chan = $l[$col_chan] if $has_channel;
	
	if ($has_segmentation) {
		$s = $l[$col_seg_s];
		$e = $l[$col_seg_e];
	}

	if (length $sox_command > 0) {
		my $tmp = $snd;
		$snd = $sox_command;
		$snd =~ s/\(file\)/$tmp/;
	}

	my $trl = "";
	if ($has_transcription and (scalar @l > $col_trl)) {
		$trl = join(" ", splice @l, $col_trl);
	}

	printf STDOUT "{
    sound-file: '$snd',
    recording-id: '$rec',
    utterance-id: '$utt',
    speaker-id: '$spk',
    segmentation: { chan: '$chan', start: '$s', end: '$e' },
    trl: '$trl'
}\n" if $verbose;
	
	if (defined $hspk{$utt}) {
		print STDERR "Error:  Duplicate utterance id $utt\n";
		exit 1;
	}

	$hwav{$rec} = $snd;
	$hwavc{$rec} = $chan;
	$hspk{$utt} = $spk;
	$htext{$utt} = $trl;
	my $seg = "$utt $rec $s $e";
	$seg .= " $chan" if $has_channel;
	push (@aseg, $seg);
}
close (FI);

if ($verbose) {
	print STDERR "Read $ln lines, imported ".(scalar keys %hwav)." recordings, ".(scalar keys %hspk)." utterances.\n";
}

# make directory
mkdir "$dir";

open (FWAV, ">$dir/wav.scp") or die "Could not open $dir/wav.scp for writing.\n";
for my $r (sort keys %hwav) {
	printf FWAV "%s %s\n", $r, $hwav{$r};
}
close (FWAV);

open (FUTT, ">$dir/utt2spk") or die "Could not open $dir/utt2spk for writing.\n";
for my $u (sort keys %hspk) {
	printf FUTT "%s %s\n", $u, $hspk{$u};
}
close (FUTT);

open (FRFC, ">$dir/reco2file_and_channel") or die "Could not open $dir/reco2file_and_channel.\n";
for my $r (sort keys %hwavc) {
	printf FRFC "%s %s %s\n", $r, $r, $hwavc{$r};
}
close (FRFC);

if ($has_transcription) {
	open (FTXT, ">$dir/text") or die "Could not open $dir/text for writing.\n";
	for my $u (sort keys %htext) {
		printf FTXT "%s %s\n", $u, $htext{$u};
	}
	close (FTXT);
}

if ($has_segmentation) {
	open (FSEG, ">$dir/segments") or die "Could not open $dir/segments for writing.\n";
	for my $s (sort @aseg) {
		printf FSEG "%s\n", $s;
	}
	close (FSEG);
}


# generate spk2utt
system ("utils/utt2spk_to_spk2utt.pl $dir/utt2spk > $dir/spk2utt");

exit 0;
