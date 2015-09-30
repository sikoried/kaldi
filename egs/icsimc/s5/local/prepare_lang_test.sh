#!/bin/bash 

# (c) 2014 Korbinian Riedhammer

# Starting from a data/lang directory, make a dir directory based on the given arpa LM
no_tests=false

. utils/parse_options.sh

if [ $# != 3 ]; then 
  echo "Usage: $0 data/lang arpa.gz data/dir"
  exit 1;
fi

if [ -f path.sh ]; then . path.sh; fi

srcdir=$1
arpagz=$2
dir=$3

[ -d $srcdir ] || ( echo "No such directory $srcdir";  exit 1; )
[ -f $arpagz ] || ( echo "No such file $arpagz";  exit 1; )

if [ -d $dir ]; then
  echo "Directory $dir already exists.";
  exit 1;
fi

# make output directory
mkdir -p $dir

# copy relevant files
for f in phones.txt words.txt L.fst L_disambig.fst phones/ oov.int oov.txt; do
	cp -r $srcdir/$f $dir/
done


# find OOVs, save to file
gunzip -c $arpagz | \
	utils/find_arpa_oovs.pl $dir/words.txt > $dir/oovs.txt

# grep -v '<s> <s>' etc. is only for future-proofing this script.  Our
# LM doesn't have these "invalid combinations".  These can cause 
# determinization failures of CLG [ends up being epsilon cycles].
# Note: remove_oovs.pl takes a list of words in the LM that aren't in
# our word list.  Since our LM doesn't have any, we just give it
# /dev/null [we leave it in the script to show how you'd do it].
echo "locale settings: LANG=$LANG LC_ALL=$LC_ALL"
gunzip -c "$arpagz" | \
   grep -v '<s> <s>' | \
   grep -v '</s> <s>' | \
   grep -v '</s> </s>' | \
   arpa2fst - | fstprint | \
   utils/remove_oovs.pl $dir/oovs.txt | \
   utils/eps2disambig.pl | utils/s2eps.pl | fstcompile --isymbols=$dir/words.txt \
     --osymbols=$dir/words.txt  --keep_isymbols=false --keep_osymbols=false | \
     fstrmepsilon > $dir/G.fst || exit 1;

echo  "Checking how stochastic G is (the first of these numbers should be small):"
fstisstochastic $dir/G.fst 

if $no_tests; then
	echo "Warning, performing no tests-- be sure to know what you're doing."
	exit 0;
fi

## Check lexicon.
## just have a look and make sure it seems sane.
echo "First few lines of lexicon FST:"
fstprint   --isymbols=$dir/phones.txt --osymbols=$dir/words.txt $dir/L.fst | head

echo Performing further checks

# Checking that L_disambig.fst is determinizable.
echo "Checking L_disambig.fst"
fstdeterminize $dir/L_disambig.fst /dev/null || echo Error determinizing L_disambig.

# Checking that G.fst is determinizable.
echo "Checking G.fst"
fstdeterminizestar $dir/G.fst /dev/null || echo Error determinizing G.


# Checking that disambiguated lexicon times G is determinizable
# Note: we do this with fstdeterminizestar not fstdeterminize, as
# fstdeterminize was taking forever (presumbaly relates to a bug
# in this version of OpenFst that makes determinization slow for
# some case).
echo "Checking composition L o G"
fsttablecompose $dir/L_disambig.fst $dir/G.fst | \
  fstdeterminizestar > /dev/null || echo "Failed to compose (L o G)"

# Checking that LG is stochastic:
fsttablecompose $dir/L_disambig.fst $dir/G.fst | \
  fstisstochastic || echo "(L o G) is not stochastic"

echo "Succeded building $dir"
