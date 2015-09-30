#!/bin/bash

# koried, 8/12/2015
# compute a few stats for data directory

if [ $# -lt 1 ]; then
  echo "usage: $0 data/dir1 [data/dir2 ...]"
  exit 1
fi

for dir in $@; do
  num_utt=$(wc $dir/utt2spk | awk '{printf "%d", $1}')
  num_spk=$(wc $dir/spk2utt | awk '{printf "%d", $1}')
  dur=$(awk '{dur+=($4-$3)} END{printf "%.2f", dur/3600}' $dir/segments)

  echo "duration:   $dur hours"
  echo "speakers:   $num_spk"
  echo "utterances: $num_utt"
  echo "avg turn dur: $(printf "%.2f" $(echo 3600*$dur/$num_utt | bc -l)) seconds"

  echo "speech by speakers (hours), average turn length (seconds)"
  for s in `awk '{print $1}' $dir/spk2utt`; do
    grep $s $dir/segments | awk -v spk=$s '{dur+=($4-$3)} END{printf "%s %.2f %.2f\n", spk, dur/3600, dur/NR}'
  done | sort -k2 -n -r

done
