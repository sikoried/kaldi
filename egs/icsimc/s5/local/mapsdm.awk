#!/usr/bin/awk -f

# read in sdm channel map from first file, apply to remaining annot files

BEGIN {
  nf = 0;
} 

{ 
  if (FNR == 1) {
    nf += 1;
  }

  if (nf > 1) { 
    if (map[$1] == "") {
      print "Missing channel mapping for meeting\n" > /dev/stderr;
      exit 1;
    }
    $3 = map[$1];
    print; 
  } else { 
    map[$1] = $2; 
  }
}
