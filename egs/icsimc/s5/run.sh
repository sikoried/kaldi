#!/bin/bash

# ICSI Meeting Corpus Recipe, (c) 2015  Korbinian Riedhammer, Remeeting, Inc.

icsimc=/mnt/disk0/data/icsimc
sph2pipe=/mnt/disk0/koried/svn/kaldi/trunk/tools/sph2pipe_v2.5/sph2pipe

# import data
local/icsimc_data_prep.sh $icsimc

# we'll run ihm and sdm
for cond in ihm sdm; do
  local/icsimc_mk_data_dir.sh --sph2pipe $sph2pipe $icsimc \
    data/local/import/annotations.$cond data/$cond/all

  # for the strict sets, get the test speaker (we're using only Bmr005 for now
  utils/filter_scp.pl -f 2 local/list.test.1 data/$cond/all/spk2mtg |\
    awk '{print $1}' | sort -u > data/local/${cond}.spk.test

  # utterances from the test meetings
  utils/filter_scp.pl -f 2 local/list.test.1 data/$cond/all/utt2mtg > data/local/${cond}.utt.test

  # all utterances from speakers excluding test speakers
  utils/filter_scp.pl --exclude -f 2 data/local/${cond}.spk.test data/$cond/all/utt2spk > data/local/${cond}.utt.train

  # this is about 
  utils/reduce_data_dir.sh data/$cond/all data/local/${cond}.utt.train data/$cond/train
  utils/reduce_data_dir.sh data/$cond/all data/local/${cond}.utt.test data/$cond/test

  utils/fix_data_dir.sh data/$cond/train
  utils/fix_data_dir.sh data/$cond/test
done


# build lang directory;  this uses some g2p-derived (and corrected) prons
local/icsimc_prepare_dict.sh
utils/prepare_lang.sh data/local/dict "(UNK)" data/local/lang_tmp data/lang

# train LM for decoding;  use ihm
# cheat: all data
cut -d' ' -f 2- data/ihm/all/text > data/local/lmtext.cheat
local/train_lm_srilm.sh --extra-words local/vocab.hes \
  data/local/lmtext.cheat data/local/lmtmp.cheat data/local/lm.cheat.gz
local/prepare_lang_test.sh data/lang data/local/lm.cheat.gz data/lang_test_cheat

# strict: only use words from training data
cut -d' ' -f 2- data/ihm/train/text > data/local/lmtext.strict
local/train_lm_srilm.sh --extra-words local/vocab.hes \
  data/local/lmtext.strict data/local/lmtmp.strict data/local/lm.strict.gz
local/prepare_lang_test.sh data/lang data/local/lm.strict.gz data/lang_test_strict

# wspk: use all speakers, exclude only test meetings/utterances
utils/filter_scp.pl --exclude data/ihm/test/utt2spk data/ihm/all/text |\
  cut -d' '  -f 2- > data/local/lmtext.wspk
local/train_lm_srilm.sh --extra-words local/vocab.hes \
  data/local/lmtext.wspk data/local/lmtmp.wspk data/local/lm.wspk.gz
local/prepare_lang_test.sh data/lang data/local/lm.wspk.gz data/lang_test_wspk

# make mfcc features;  note that we compute duplicates here-- someone may not want to run `all`.
nj=40
mfccdir=mfcc
for cond in ihm sdm; do
  for x in all train test; do
    steps/make_mfcc.sh --cmd "$train_cmd" --nj $nj \
      data/$cond/$x exp/$cond/make_mfcc/$x exp/$cond/$mfccdir || exit 1;

    # just to be sure (some mfcc may fail)
    utils/fix_data_dir.sh data/$cond/$x

    steps/compute_cmvn_stats.sh data/$cond/$x exp/$cond/make_mfcc/$x exp/$cond/$mfccdir || exit 1;
  done
done


# run single condition for now;  could be outsourced to other script
cond=ihm


# subset training data
utils/subset_data_dir.sh --shortest data/$cond/train 10000 data/$cond/train_10k
local/remove_dup_utts.sh 50 data/$cond/train_10k data/$cond/train_10k_nodup

utils/subset_data_dir.sh --first data/$cond/train 25000 data/$cond/train_25k
local/remove_dup_utts.sh 50 data/$cond/train_25k data/$cond/train_25k_nodup


# train AM;  we'll use the same number of jobs as we have speakers: most of the speakers are "short"
steps/train_mono.sh --nj 44 --cmd "$train_cmd" \
  data/$cond/train_10k_nodup data/lang exp/$cond/mono0a || exit 1;

# for some reason, 25k has only 26 speakers
steps/align_si.sh --nj 26 --cmd "$train_cmd" \
  data/$cond/train_25k_nodup data/lang exp/$cond/mono0a exp/$cond/mono0a_ali || exit 1;
steps/train_deltas.sh --cmd "$train_cmd" \
  2500 20000 data/$cond/train_25k_nodup data/lang exp/$cond/mono0a_ali exp/$cond/tri1 || exit 1;

steps/align_si.sh --nj 26 --cmd "$train_cmd" \
  data/$cond/train_25k_nodup data/lang exp/$cond/tri1 exp/$cond/tri1_ali || exit 1;
steps/train_deltas.sh --cmd "$train_cmd" \
  2500 25000 data/$cond/train_25k_nodup data/lang exp/$cond/tri1_ali exp/$cond/tri2 || exit 1;

steps/align_si.sh --nj 44 --cmd "$train_cmd" \
  data/$cond/train data/lang exp/$cond/tri1 exp/$cond/tri2_ali || exit 1;
steps/train_lda_mllt.sh --cmd "$train_cmd" \
  --splice-opts "--left-context=3 --right-context=3" \
  2500 40000 data/$cond/train data/lang exp/$cond/tri2_ali exp/$cond/tri3a || exit 1;

steps/align_fmllr.sh --nj 44 --cmd "$train_cmd" \
  data/$cond/train data/lang exp/$cond/tri3a exp/$cond/tri3a_ali || exit 1;
steps/train_sat.sh  --cmd "$train_cmd" \
  3500 60000 data/$cond/train data/lang exp/$cond/tri3a_ali exp/$cond/tri4a || exit 1;

# test the tri4a system, both on strict and with speaker lm data
( utils/mkgraph.sh data/lang_test_strict exp/$cond/tri4a exp/$cond/tri4a/graph_strict && \
  steps/decode_fmllr.sh --nj 8 --cmd "$decode_cmd" --config conf/decode.config \
    exp/$cond/tri4a/graph_strict data/$cond/test exp/$cond/tri4a/decode_test_strict ) &

( utils/mkgraph.sh data/lang_test_wspk exp/$cond/tri4a exp/$cond/tri4a/graph_wspk && \
  steps/decode_fmllr.sh --nj 8 --cmd "$decode_cmd" --config conf/decode.config \
    exp/$cond/tri4a/graph_wspk data/$cond/test exp/$cond/tri4a/decode_test_wspk ) &

wait

# let's try some cheating: add speakers which also appear in test set, but balance
# the data by removing ~50% of me013 as well as speakers with less than 10min of speech
utils/filter_scp.pl --exclude local/spk.lt10 data/$cond/all/spk2utt | awk -v n=8000 '{ if ($1 == "me013") { 
    printf $1; 
    for (i=1;i<=n;i++) printf " %s", $i; 
    printf "\n"; 
  } else { print; }}' | utils/spk2utt_to_utt2spk.pl | \
  utils/filter_scp.pl --exclude data/local/${cond}.utt.test > data/local/${cond}.utt.train_bal
utils/reduce_data_dir.sh data/$cond/all data/local/${cond}.utt.train_bal data/$cond/train_bal
utils/fix_data_dir.sh data/$cond/train_bal

steps/align_fmllr.sh --nj 40 --cmd "$train_cmd" \
  data/$cond/train_bal data/lang exp/$cond/tri4a exp/$cond/tri4a_ali_bal || exit 1;
steps/train_sat.sh  --cmd "$train_cmd" \
  4500 100000 data/$cond/train_bal data/lang exp/$cond/tri4a_ali_bal exp/$cond/tri5c || exit 1;

# test this system;  remember: test speakers are in training!
( utils/mkgraph.sh data/lang_test_strict exp/$cond/tri5c exp/$cond/tri5c/graph_strict && \
  steps/decode_fmllr.sh --nj 8 --cmd "$decode_cmd" --config conf/decode.config \
    exp/$cond/tri5c/graph_strict data/$cond/test exp/$cond/tri5c/decode_test_strict ) &

( utils/mkgraph.sh data/lang_test_wspk exp/$cond/tri5c exp/$cond/tri5c/graph_wspk && \
  steps/decode_fmllr.sh --nj 8 --cmd "$decode_cmd" --config conf/decode.config \
    exp/$cond/tri5c/graph_wspk data/$cond/test exp/$cond/tri5c/decode_test_wspk ) &

wait


# gmm multi-condition training (continuing without cheat)
cond=mc
part=train_bal  # partition to base this mc training on
# first combine data;  this will fail to validate as we have two competing cmvn files.
utils/combine_data.sh data/$cond/$part data/{ihm,sdm}/$part
mv data/$cond/$part/.backup/* data/$cond/$part/
rm data/$cond/$part/cmvn.scp
steps/compute_cmvn_stats.sh data/$cond/$part exp/$cond/make_mfcc exp/$cond/mfcc

# use ihm non-cheating system (tri4a) to align data and train tri5
steps/align_fmllr.sh --nj 40 --cmd "$train_cmd" \
  data/$cond/$part data/lang exp/ihm/tri4a exp/$cond/tri4a_ali_$part || exit 1;
steps/train_sat.sh  --cmd "$train_cmd" \
  5000 120000 data/$cond/$part data/lang exp/$cond/tri4a_ali_$part exp/$cond/tri5 || exit 1;

# test on both ihm and sdm condition
utils/mkgraph.sh data/lang_test_wspk exp/$cond/tri5 exp/$cond/tri5/graph_wspk

steps/decode_fmllr.sh --nj 8 --cmd "$decode_cmd" --config conf/decode.config \
  exp/$cond/tri5/graph_wspk data/ihm/test exp/$cond/tri5/decode_ihm_test_wspk &
steps/decode_fmllr.sh --nj 8 --cmd "$decode_cmd" --config conf/decode.config \
  exp/$cond/tri5/graph_wspk data/sdm/test exp/$cond/tri5/decode_sdm_test_wspk &
wait

lm=rt07.p1e-9.3bo
steps/decode_fmllr.sh --nj 1 --num-threads 8 --cmd "$decode_cmd" --config conf/decode.config \
  exp/$cond/tri5/graph_$lm data/ihm/test exp/$cond/tri5/decode_ihm_test_$lm &
steps/decode_fmllr.sh --nj 1 --num-threads 8 --cmd "$decode_cmd" --config conf/decode.config \
  exp/$cond/tri5/graph_$lm data/sdm/test exp/$cond/tri5/decode_sdm_test_$lm &

lm=mod9_icsimc_lp_swbd_yc-kn-i.min5.p1e-8.3bo
steps/decode_fmllr.sh --nj 1 --num-threads 8 --cmd "$decode_cmd" --config conf/decode.config \
  exp/$cond/tri5/graph_$lm data/ihm/test exp/$cond/tri5/decode_ihm_test_$lm &
steps/decode_fmllr.sh --nj 1 --num-threads 8 --cmd "$decode_cmd" --config conf/decode.config \
  exp/$cond/tri5/graph_$lm data/sdm/test exp/$cond/tri5/decode_sdm_test_$lm &
wait

lm=mod9_icsimc_lp_swbd_yc-kn-i.min5.p1e-8.3bo
steps/decode_fmllr.sh --nj 1 --num-threads 20 --cmd "$decode_cmd" --config conf/decode.config \
  exp/$cond/tri5/graph_$lm data/mod9/test-00-n40 exp/$cond/tri5/decode_test-00-n40_$lm &

lm=rt07.p1e-9.3bo
steps/decode_fmllr.sh --nj 1 --num-threads 20 --cmd "$decode_cmd" --config conf/decode.config \
  exp/$cond/tri5/graph_$lm data/mod9/test-00-n40 exp/$cond/tri5/decode_test-00-n40_$lm &

# dnn recipe

