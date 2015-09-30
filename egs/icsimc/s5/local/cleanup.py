#!/usr/bin/env python

# (c) 2015  Remeeting, Inc.
#
# Apache 2.0
#
# Clean up ICSI transcriptions;  gets input from mrt_tag.pl | mrt2list.pl

import os
import re
import sys
import fileinput

unk = '(UNK)'
breath = '(BREATH)'
laugh = '(LAUGH)'
cough = '(COUGH)'
noise = '(NOISE)'
foreign = '(UNK)'

for line in fileinput.input():
    m, spk, ch, s, e, t = line.split(' ', 5)

    nw = 0
    proc = list()
    for w in t.split():
        if w.startswith("'"):  # foreign words
            proc.append(foreign)
            continue

        w = re.sub(r'[".:;]', '', w.upper())
        if w.startswith('(') or w.endswith(')'):
            # map to a class of noise
            if 'UNK' in w:
                proc.append(unk)
            elif 'LAUGH' in w:
                proc.append(laugh)
            elif 'COUGH' in w:
                proc.append(cough)
            elif 'BREATH' in w or 'HALE' in w:
                proc.append(breath)
            elif 'VOCAL' in w:
                proc.append(unk)
            else:
                proc.append(noise)
            continue
        if w.startswith('-'):
            continue

        w = re.sub(r'[,!?]', '', w)  # punct.
        if w == 'O_K':
            nw += 1
            proc.append('OKAY')
            continue

        w = re.sub(r'\A-', r' ', w)  # "thought" dashes
        w = re.sub(r'_-', '_ ', w)  # S_- (aborted or letter/word acronym, e.g. I_-triple-E_)
        w = re.sub(r'-_', ' ', w)  # word-_S (aborted or letter/word acronym, e.g. Trans-_I_P)

        w = re.sub(r'([A-Z])-([A-Z])', r'\1 \2', w)  # time-line
        w = re.sub(r'([A-Z])-([A-Z])', r'\1 \2', w)  # time-line
        w = re.sub(r'\bMM HMM\b', 'MM-HMM', w)  # frequently used, so restore :-(
        w = re.sub(r'\bUH HUH\b', 'UH-HUH', w)  # frequently used, so restore :-(
        
        w = re.sub(r'_([A-Z])S\Z', r"_ \1_'S", w)  # A_P_Is -> A_ P_ I_'S
        w = re.sub(r'([A-Z]{2,})_', r'\1', w)  # TRANS_
        w = re.sub(r'_([A-Z]{2,})', r'\1', w)  # _TRANS

        w = re.sub(r'_([A-Z])\Z', r'_ \1_', w)  # chop off last letter of acronym
        w = re.sub(r'\A([A-Z]_)', r'\1 ', w)  # chop off first
        w = re.sub(r"([A-Z]_)(?![' ])", r'\1 ', w)  # chop up remaining ones (but last)


        w = re.sub(r'\A([AI])-\Z', r'\1', w)  # A-  I- as special cases
        w = re.sub(r'[A-Z]+-\Z', unk, w)  # aborted words
        w = re.sub(r'[A-Z]+-\s', unk + ' ', w)  # aborted words

        w = w.replace("'" + unk, '')  # TEHY'(UNK) to THEY

        w = re.sub(r'\s\s+', ' ', w).strip()

        if w:
            nw += 1
            proc.append(w)

    
    if nw:
        print "%s %s %s %s %s %s" % (m, spk, ch, s, e, ' '.join(proc))
