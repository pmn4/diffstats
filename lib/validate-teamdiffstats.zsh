#!/bin/zsh
# Validate that codeowners_for() reproduces GitHub's required-reviewer set.
#
# For each PR: take the changed files, resolve owners with our matcher using the
# CODEOWNERS blob as of the PR's base commit, and compare the resulting team set
# against the teams GitHub actually requested for review.
#
# Only PRs with no submitted reviews are used: once a team member reviews,
# GitHub drops the team from reviewRequests, which would make our set look like
# a superset for reasons unrelated to matching.
#
# Usage: validate-teamdiffstats.zsh <pr-number> [<pr-number> ...]

emulate -L zsh
setopt extended_glob

source ${0:A:h}/changestats.zsh

# Set to the owner/name of the repository whose PRs you want to validate.
REPO=${DIFFSTATS_VALIDATE_REPO:?set DIFFSTATS_VALIDATE_REPO to owner/name}
typeset -i n_ok=0 n_bad=0 n_skip=0

for pr in $@; do
  meta=$(gh pr view $pr --repo $REPO \
    --json number,isDraft,baseRefOid,reviewRequests,latestReviews,files 2>/dev/null)
  [[ -z $meta ]] && { print -r -- "PR $pr: could not fetch"; continue }

  base=$(print -r -- "$meta" | jq -r '.baseRefOid')

  # Ground truth from the timeline: every team GitHub requested, minus any that
  # were explicitly un-requested. reviewRequests alone is incomplete, because a
  # team disappears from it as soon as one of its members submits a review.
  timeline=$(gh api "repos/$REPO/issues/$pr/timeline" \
    --paginate -H "Accept: application/vnd.github+json" 2>/dev/null)
  want=(${(f)"$(print -r -- "$timeline" | jq -r '
      [ .[] | select(.event=="review_requested")     | .requested_team.slug // empty ] as $req
    | [ .[] | select(.event=="review_request_removed")| .requested_team.slug // empty ] as $rm
    | ($req - $rm) | unique | sort | .[]')"})
  files=(${(f)"$(print -r -- "$meta" | jq -r '.files[].path')"})

  # CODEOWNERS as of the PR's base commit.
  co=$(mktemp "${TMPDIR:-/tmp}/co-$pr-$$-XXXXXX")
  gh api "repos/$REPO/contents/.github/CODEOWNERS?ref=$base" \
    --jq '.content' 2>/dev/null | base64 -d > $co
  if [[ ! -s $co ]]; then
    print -r -- "PR $pr: could not fetch CODEOWNERS at $base"
    rm -f $co; continue
  fi
  codeowners_load $co
  rm -f $co

  typeset -A seen
  for f in $files; do
    for o in $(codeowners_for $f); do
      seen[${${o#@}##*/}]=1
    done
  done
  got=(${(ko)seen})
  unset seen

  # GitHub does not request review from a team the PR author cannot be reviewed
  # by, and only teams appear in reviewRequests, so compare team sets directly.
  # `claude` is the AI review bot, requested on every PR by automation. It is
  # not a code owner, so it is not something this table should reproduce.
  want=(${want:#claude})

  missing=(${got:|want})   # we found, GitHub did not request
  extra=(${want:|got})     # GitHub requested, we missed

  if (( ${#missing} == 0 && ${#extra} == 0 )); then
    (( n_ok++ ))
    print -r -- "PR $pr: ✅ MATCH  (${#got} teams: ${(j:, :)got})"
  else
    (( n_bad++ ))
    print -r -- "PR $pr: ❌ DIFF"
    print -r -- "    files:      ${#files}"
    print -r -- "    github:     ${(j:, :)want}"
    print -r -- "    computed:   ${(j:, :)got}"
    (( ${#extra} ))   && print -r -- "    MISSED:     ${(j:, :)extra}"
    (( ${#missing} )) && print -r -- "    EXTRA:      ${(j:, :)missing}"
  fi
done

print -r -- ""
print -r -- "match=$n_ok  diff=$n_bad  skipped=$n_skip"
