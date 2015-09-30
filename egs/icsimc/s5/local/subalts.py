#!/usr/bin/env python

# substitute alternatives

import os
import sys
import fileinput

if len(sys.argv) < 2:
    print "usage:  %s [--stm] substfile col-start [input]" % sys.argv[0]
    sys.exit(1)

stm = False
if sys.argv[1] == '--stm':
    stm = True
    sys.argv.pop(1)

sub = dict()
with open(sys.argv.pop(1)) as subsf:
    for line in subsf:
        fr, to = line.strip().split()
        sub[fr] = to

col = int(sys.argv.pop(1))

for line in fileinput.input():
    arr = line.split()
    for i in range(col, len(arr)):
        # mark non-words as optional
        if stm and arr[i].startswith('(') and arr[i].endswith(')'):
            arr[i] = "{ %s / @ }" % arr[i]
            continue

        # if we potentially sub this word, allow both versions to be scored
        if arr[i] in sub:
            if stm:
                arr[i] = "{ %s / %s }" % (arr[i], sub[arr[i]])
            else:
                arr[i] = sub[arr[i]]

    print ' '.join(arr)
