#!/usr/bin/env python

# (c) 2015  Remeeting, Inc.
#
# Apache 2.0
#
# Map the `far` channel to what's in the SDM mapping file

import os
import sys
import fileinput

chmap = dict()
with open(sys.argv[1]) as mapfile:
    for line in mapfile:
        m, ch = line.split()
        chmap[m] = ch

sys.argv.pop(1)

for line in fileinput.input():
    m, spk, ch, _ = line.split(' ', 3)

    if ch == 'far':
        if m in chmap:
            ch = chmap[m]
        else:
            raise Exception('Missing channel map for meeting ' + m)

    print "%s %s %s %s" % (m, spk, ch, _),
