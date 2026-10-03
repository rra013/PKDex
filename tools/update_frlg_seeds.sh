#!/bin/zsh
# Downloads the FireRed/LeafGreen farmed seed lists that the Finder's Initial
# Seed search bundles (PKReference/frlg-seeds-*.csv), from the RNG
# community's public sheets, the same ones Ten Lines builds from
# (https://github.com/Lincoln-LM/ten-lines, generate_ten_lines_precalc.py).
# Keep the list in step with `FRLGSeedSheet` in PKReference/FRLGSeeds.swift;
# FRLGSeedsTests checks every sheet has a bundled copy. In the app, Update
# Seed Lists downloads the same sheets.
set -euo pipefail
cd "$(dirname "$0")/.."
base="https://docs.google.com/spreadsheets/d"
typeset -A sheets
sheets=(
  fr_eng        "1ZNchTvoCpHFVPBscEJZG3JaaqR41D8VVnbXb23fzc44/gviz/tq?tqx=out:csv&gid=0"
  lg_eng        "12TUcXGbLY_bBDfVsgWZKvqrX13U6XAATQZrYnzBKP6Y/gviz/tq?tqx=out:csv&sheet=Leaf%20Green%20Seeds"
  fr_jpn_1_0    "1xSYuAuGSZQ4JbgQN262cfo80_A2CYko74bYGzl5ABTA/gviz/tq?tqx=out:csv&sheet=JPN%20Fire%20Red%201.0%20Seeds"
  fr_jpn_1_1    "1aQeWaZSi1ycSytrNEOwxJNoEg-K4eItYagU_dh9VIeU/gviz/tq?tqx=out:csv&sheet=JPN%20Fire%20Red%201.0%20Seeds"
  lg_jpn        "1LSRVD0_zK6vyd6ettUDfaCFJbm00g451d8s96dqAbA4/gviz/tq?tqx=out:csv&sheet=JPN%20Leaf%20Green%20Seeds"
  fr_eng_mgba   "1aWo6FAjkLIut5TIKior4_04PlGessxUJhE8YWz_nQwc/gviz/tq?tqx=out:csv&sheet=Fire%20Red%20Seeds"
  lg_eng_mgba   "1YiQiII2v3AJK6RANMsQcBzVLk9dO6L99Zxt9FsCyKrI/gviz/tq?tqx=out:csv&sheet=Leaf%20Green%20Seeds"
  fr_eng_nx     "1mbn2-XAtmV7HZ1p4esgvUG710VX6FlfhN_HYL_zLJSk/gviz/tq?tqx=out:csv&sheet=FireRed%20Seeds"
  lg_eng_nx     "1mbn2-XAtmV7HZ1p4esgvUG710VX6FlfhN_HYL_zLJSk/gviz/tq?tqx=out:csv&sheet=LeafGreen%20Seeds"
  fr_jpn_nx     "1mbn2-XAtmV7HZ1p4esgvUG710VX6FlfhN_HYL_zLJSk/gviz/tq?tqx=out:csv&sheet=JPN%20FireRed%20Seeds"
  lg_jpn_nx     "1mbn2-XAtmV7HZ1p4esgvUG710VX6FlfhN_HYL_zLJSk/gviz/tq?tqx=out:csv&sheet=JPN%20LeafGreen%20Seeds"
)
for name sheet in ${(kv)sheets}; do
  curl -sSfL "$base/$sheet" -o "PKReference/frlg-seeds-$name.csv.tmp"
  [[ $(wc -l < "PKReference/frlg-seeds-$name.csv.tmp") -gt 100 ]] || { echo "$name: too short"; exit 1; }
  mv "PKReference/frlg-seeds-$name.csv.tmp" "PKReference/frlg-seeds-$name.csv"
  echo "$name: $(wc -l < PKReference/frlg-seeds-$name.csv) lines"
done
date +%Y-%m-%d > PKReference/frlg-seeds-date.txt
