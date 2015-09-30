#!/bin/bash

# Prepare lexicon for ICSI (cmudict + some manual and phonetizised ones)

echo "$0 $@"

dir=data/local/dict
mkdir -p $dir

# make sure we're sorting correctly
LC_ALL=C

# we're basing it on cmudict;  this follows wsj/s5/local/wsj_prepare_dict.sh
svn co  https://svn.code.sf.net/p/cmusphinx/code/trunk/cmudict \
  $dir/cmudict || exit 1;

cat $dir/cmudict/cmudict.0.7a.symbols | perl -ane 's:\r::; print;' | \
   perl -e '
    while(<>) {
      chop; m:^([^\d]+)(\d*)$: || die "Bad phone $_"; 
      $phones_of{$1} .= "$_ "; 
    }
    foreach $list (values %phones_of) { print $list . "\n"; } ' \
          > $dir/nonsilence_phones.txt || exit 1;

(echo SIL; echo SPN; echo NSN; echo BRE; echo COU; echo LAU) > $dir/silence_phones.txt
echo SIL > $dir/optional_silence.txt

cat $dir/silence_phones.txt| awk '{printf("%s ", $1);} END{printf "\n";}' > $dir/extra_questions.txt || exit 1;
cat $dir/nonsilence_phones.txt | perl -e 'while(<>){ foreach $p (split(" ", $_)) {
  $p =~ m:^([^\d]+)(\d*)$: || die "Bad phone $_"; $q{$2} .= "$p "; } } foreach $l (values %q) {print "$l\n";}' \
     >> $dir/extra_questions.txt || exit 1;

# convert the lexicon to plain text, replace A. by A_
grep -v ';;;' $dir/cmudict/cmudict.0.7a | \
  perl -ane 'if(!m:^;;;:){ s:(\S+)\(\d+\) :$1 :; print; }' | \
    sed -e 's:^\([A-Z]\)\.:\1_:' > $dir/lexicon1_raw_nosil.txt || exit 1;

# add icsimc dict, hesitations as (HES) and original token (e.g. EHM)
cat local/dict.icsimc >> $dir/lexicon1_raw_nosil.txt || exit 1;
cut -d ' ' -f 1,3- local/dict.hes >> $dir/lexicon1_raw_nosil.txt || exit 1;
cut -d ' ' -f 2- local/dict.hes >> $dir/lexicon1_raw_nosil.txt || exit 1;

# the sort | uniq is to remove a duplicated pron from cmudict.
# add prons derived from cmudict-trained  OOVs
(echo '!SIL SIL'; echo '(BREATH) BRE'; echo '(COUGH) COU'; echo '(LAUGH) LAU'; echo '(UNK) SPN'; echo '(NOISE) NSN'; ) | \
   cat - $dir/lexicon1_raw_nosil.txt | sort | uniq > $dir/lexicon.txt || exit 1;

# just to make sure
rm -f $dir/lexiconp.txt

echo "Dictionary preparation succeeded"

