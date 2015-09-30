#!/bin/bash

# (c) 2015  Remeeting, Inc.   (Korbinian Riedhammer)
#
# ICSI Meeting Corpus data preparation
#
# Apache 2.0


# to be run from ../

set -e

. ./path.sh

if [ $# != 1 ]; then
  echo "usage:  $0 /path/to/icsimc"
  exit 1
fi

echo "$0 $@"

icsimc=$1
tmpdata=data/local/import

LC_ALL=C

# ensure we got XML::Parser
perl -e 'use XML::Parser' || "Please make sure perl finds XML::Parser"

# meeting list
mkdir -p $tmpdata
find $icsimc/transcripts/ -name "B*.mrt" | sort | \
  perl -e 'while (<>) { if (m:(B[a-z]{2}[0-9]{3}):) { print "$1 $_"; }}' \
  > $tmpdata/meetings


# annotations, cleaned-up transcript (excludes utts without proper words)
for i in `awk '{print $2}' $tmpdata/meetings`; do
  local/mrt_tag.pl -t $i | local/mrt2list.pl - | sort -k4,4n
done > $tmpdata/annotations.raw

# clean up transcript
local/cleanup.py $tmpdata/annotations.raw > $tmpdata/annotations


# we're not messing with the speakers for now as we're looking for ihm data.
if false; then
  mv $tmpdata/annotations{,.unmapped}
  # get sdm mapping to map from "far" to the appropriate channel
  egrep '^B[a-z]{2}[0-9]{3}' $icsimc/doc/sdm.txt | sed -e 's:/: :' -e 's:.sph$::' | \
    sort > $tmpdata/sdm
  # Bmr003 is chanF (personal communication with Adam; fixed at ICSI local copy)
  echo "Bmr003 chanF" >> $tmpdata/sdm

  local/mapsdm.py $tmpdata/sdm $tmpdata/annotations.unmapped > $tmpdata/annotations
fi


# get ihm data
awk '{if ($3 != "far") print;}' $tmpdata/annotations > $tmpdata/annotations.ihm

# get sdm data (use map file), remove outlier speakers "none" and "xe902"
local/mapsdm.awk $tmpdata/sdm $tmpdata/annotations |\
  grep -v none | grep -v xe902 > $tmpdata/annotations.sdm

echo "Stored annotations in $tmpdata/annotations.{ihm,sdm}"
exit 0

