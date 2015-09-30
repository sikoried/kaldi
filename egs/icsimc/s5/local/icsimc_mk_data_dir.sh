#!/bin/bash

# create data dir from annots file

sph2pipe=../../../tools/sph2pipe_v2.5/sph2pipe

echo "$0 $@"

[ -f ./path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;

if [ $# != 3 ]; then
  echo "usage:  $0 [--sph2pipe path/to/sph2pipe] path/to/icsimc annotfile data/output"
  exit 1
fi

if [ ! -x $sph2pipe ]; then
  echo "Could not locate sph2pipe at $sph2pipe; use --sph2pipe to set location"
  exit 1
fi

icsimc=$1
annotf=$2
outdir=$3

if [ ! -d $icsimc ]; then
  echo "No such directory $icsimc"
  exit 1
fi

mkdir -p $outdir

# we'll be sorting unix style
LC_ALL=C

# recordings, e.g. Bdb001_chan3
awk -v sph2pipe=$sph2pipe -v icsimc=$icsimc '{
    printf "%s_%s %s -p -f wav %s/audio/%s/%s.sph |\n", $1, $3, sph2pipe, icsimc, $1, $3;
  }' $annotf | sort -u > $outdir/wav.scp

# recording to file and channel, e.g. Bdb001_chan3 Bdb001_chan3 A
# kind of pointless, as file==recording and all of them are mono... but sclite wants it
awk '{
    printf "%s_%s %s_%s A\n", $1, $3, $1, $3;
  }' $annotf | sort -u > $outdir/reco2file_and_channel


# segments, e.g. me011_Bdb001_chan3_0000005_0000186 Bdb001_chan3 0.056 1.861 
awk '{
    printf "%s_%s_%s_%07d_%07d %s_%s %s %s\n", $2, $1, $3, int(100*$4), int(100*$5), $1, $3, $4, $5;
  }' $annotf | sort > $outdir/segments

# utt2spk, e.g. me011_Bdb001_chan3_0000005_0000186 me011 
awk '{
    printf "%s_%s_%s_%07d_%07d %s\n", $2, $1, $3, int(100*$4), int(100*$5), $2;
  }' $annotf | sort > $outdir/utt2spk

# utt2mtg, e.g. me011_Bdb001_chan3_0000005_0000186 Bdb001 
awk '{
    printf "%s_%s_%s_%07d_%07d %s\n", $2, $1, $3, int(100*$4), int(100*$5), $1;
  }' $annotf | sort > $outdir/utt2mtg

# spk2mtg, e.g. me011 Bdb001 
awk '{
    printf "%s %s\n", $2, $1;
  }' $annotf | sort -u > $outdir/spk2mtg
utils/utt2spk_to_spk2utt.pl $outdir/spk2mtg > $outdir/mtg2spk

# text, e.g. me011_Bdb001_chan3_0000005_0000186 YEAH WE HAD A LONG DISCUSSION ABOUT
awk '{
    printf("%s_%s_%s_%07d_%07d", $2, $1, $3, int(100*$4), int(100*$5));
    for (i=6; i<=NF; i++) printf " %s", $i;
    printf "\n";
  }' $annotf | sort > $outdir/text


utils/utt2spk_to_spk2utt.pl $outdir/utt2spk > $outdir/spk2utt

# create stm file
awk '{print $2, $1}' local/dict.hes > local/tohes.map
awk '{
    printf "%s_%s A %s %.2f %.2f", $1, $3, $2, $4, $5; 
    for (i=6; i<=NF; i++) printf " %s", $i; 
    printf "\n";
}' $annotf | sort +0 -1 +1 -2 +3nb -4 | local/subalts.py --stm local/tohes.map 5 > $outdir/stm

# check if everything is ok
utils/validate_data_dir.sh --no-feats $outdir

# some stats: speech per speaker
for i in `awk '{print $1}' $outdir/spk2mtg | sort -u`; do grep ^$i $outdir/segments | awk -v spk=$i '{dur+=($4-$3)} END{print spk, dur/3600}'; done > $outdir/spk2dur

exit 0
