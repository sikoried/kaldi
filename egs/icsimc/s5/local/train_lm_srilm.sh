#!/bin/bash

# koried, 8/12/2015
# train basic n-gram model with limited vocabulary;  optionally specify words
# to add to vocabulary

extra_words=
order=3
srilm_opts="-wbdiscount -interpolate"

. ./path.sh
. utils/parse_options.sh

if [ $# != 3 ]; then
	echo "usage:  $0 [--extra-words file --srilm-opts "-prune 1e-10" --order 4] text tempdir arpa.out.gz"
  echo "default order: $order, default options: $srilm_opts"
	exit 1;
fi

if [[ ! `which ngram-count` ]]; then
  echo "$0:  could not find ngram-count in \$PATH"
  exit 1
fi

text=$1
tmpdir=$2
arpa=$3

mkdir -p $tmpdir

# make sure we're operating in the correct locale
LC_ALL=C

# determine vocabulary
sed -e 's: :\n:g' $text | sort -u > $tmpdir/vocab || exit 1

if [ "$extra_words" != "" ]; then
  echo "Adding extra words from $extra_words"
  mv $tmpdir/vocab $tmpdir/vocab.orig
  cat $extra_words $tmpdir/vocab.orig | sort -u > $tmpdir/vocab || exit 1
fi

# assume that you have SRILM in your path from a proper installation
echo "Estimating LM"
ngram-count -text $text -order $order $srilm_opts \
  -no-sos -no-eos \
  -limit-vocab -vocab $tmpdir/vocab \
  -unk -map-unk '(UNK)' -lm $arpa

echo "Done."
exit 0

