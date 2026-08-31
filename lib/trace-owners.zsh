#!/bin/zsh
# trace-owners.zsh <codeowners-file> <path> [<path> ...]
# Prints every CODEOWNERS rule that matches each path, in file order, so the
# last one shown is the winner under GitHub semantics.
emulate -L zsh
setopt extended_glob
source ${0:A:h}/changestats.zsh

co=$1; shift
codeowners_load $co

for f in $@; do
  print -r -- "=== $f"
  found=0
  for (( i = 1; i <= ${#CO_PATTERNS}; i++ )); do
    for g in ${(f)"$(_co_glob ${CO_PATTERNS[i]})"}; do
      if [[ $f == ${~g} ]]; then
        owners=${CO_OWNERS[i]}
        print -r -- "    rule#$i  ${CO_PATTERNS[i]}  ->  ${owners:-<OWNERLESS>}"
        found=1
        break
      fi
    done
  done
  (( found )) || print -r -- "    <no matching rule>"
  print -r -- "    WINNER: ${$(codeowners_for $f):-<none>}"
done
