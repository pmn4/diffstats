#!/bin/zsh
# changestats.zsh — shared library for `diffstats` and `teamdiffstats`.
#
# WHY THIS FILE EXISTS
# The two scripts each carried their own copy of the code/test classifier. The
# copies drifted: teamdiffstats inherited awk's regex delimiter as a literal
# (`test_/`) and lost its backslashes to zsh quoting, so `\.cy\.` degraded to
# `.cy.` with any-char wildcards. That matched `billing_cycle`, `privacy`,
# `legacy` and `latest_`, and scored the whole 899-file billing_cycle domain as
# test work. One classifier, one owner-resolver, both used by both scripts.
#
# OWNERSHIP MODEL
# codeowners_for() reproduces GitHub CODEOWNERS semantics, because the team rows
# in teamdiffstats must equal the required-reviewer list GitHub shows on the PR:
#   * last matching rule wins  (NOT deepest-directory, NOT first match)
#   * every owner on the winning rule is credited  (NOT just the first)
#   * a rule with a pattern but no owners REMOVES ownership for those paths
#   * patterns use gitignore syntax: path-component matching, not prefix
#     matching, so `/libs/Form` does not match `/libs/FormWizard/x.ts`
#
# CLASSIFICATION JUDGEMENT CALLS (documented so they can be argued with)
#   * `cassettes/` -> generated. VCR cassettes are recorded, not authored.
#   * `factories/` -> code. Test-data factories are test support, but the repo
#     also has production factories and the path alone cannot tell them apart.
#   * `app/**/test_data/` -> code. A real production seeding surface.
#   * `send_test_* / create_test_* / delete_test_* / seed_test_*` -> code.
#     Production entry points that happen to send test payloads.

# ---------------------------------------------------------------------------
# classify_path <path>  ->  prints "code" | "test" | "generated"
# ---------------------------------------------------------------------------
classify_path() {
  emulate -L zsh
  setopt extended_glob

  local f=$1
  local base=${f:t}

  # --- generated -----------------------------------------------------------
  # Recorded or machine-emitted content. Authorship credit does not apply.
  case $f in
    (generated/*|*/generated/*) print generated; return ;;
    (cassettes/*|*/cassettes/*) print generated; return ;;
  esac
  case $base in
    (*.snap) print generated; return ;;
  esac

  # --- test directories ----------------------------------------------------
  # This repo's dominant convention is directory-based, not basename-based:
  # ~3,400 files live under a `tests/` component. Checked before the
  # production-surface overrides so a fixture under tests/ stays a test.
  case $f in
    (tests/*|*/tests/*)         print test; return ;;
    (test/*|*/test/*)           print test; return ;;
    (__tests__/*|*/__tests__/*) print test; return ;;
    (__test__/*|*/__test__/*)   print test; return ;;
    (cypress/*|*/cypress/*)     print test; return ;;
  esac

  # --- production surfaces that read like tests ----------------------------
  # Must lose to the tests/ check above, must beat the basename checks below.
  case $f in
    (test_data/*|*/test_data/*) print code; return ;;
  esac
  case $base in
    (send_test_*|create_test_*|delete_test_*|seed_test_*) print code; return ;;
  esac

  # --- test basenames ------------------------------------------------------
  case $base in
    (conftest.py)       print test; return ;;
    (test_*.py)         print test; return ;;
    (*_test.py)         print test; return ;;
  esac
  # Frontend conventions. These scripts run across several repositories, and the
  # convention is not the same in each. Measured across four real ones:
  #   monolith        1546 .test.*     0 .spec.*
  #   webapp           196 .test.*     0 .spec.*
  #   plugin-repo        0 .test.*   128 .spec.ts   <- spec only
  #   platform-repo    519 .test.*    16 .spec.ts
  # So `.spec.` must be a test signal, or every test in plugin-repo reads as
  # production code.
  #
  # The extension list is explicit rather than a wildcard because the monolith
  # has 72 `tsconfig.spec.json` build-config files that must stay code. Note for
  # future edits: zsh's `?` is any-single-char, NOT an optional quantifier --
  # write `ts(x|)` or `(ts|tsx)` for "ts or tsx", never `ts(x)?`.
  case $base in
    (*.test.(ts|tsx|js|jsx|mjs|cjs))    print test; return ;;
    (*.spec.(ts|tsx|js|jsx|mjs|cjs))    print test; return ;;
    (*.cy.(ts|tsx|js|jsx))              print test; return ;;
    (*.stories.(ts|tsx|js|jsx|mdx))     print test; return ;;
  esac

  print code
}

# ---------------------------------------------------------------------------
# codeowners_load <codeowners-file>
#   Fills the global arrays CO_PATTERNS and CO_OWNERS, index-aligned, in file
#   order. Owner-less rules are kept: they must still win as the last match.
# ---------------------------------------------------------------------------
typeset -ga CO_PATTERNS CO_OWNERS
# Flattened candidate globs, precomputed at load time. CO_GLOB[j] is a zsh glob
# and CO_GLOB_RULE[j] is the index of the rule it came from. Precomputing keeps
# the per-file cost to one array walk instead of re-translating 1,500 patterns
# for every changed file.
typeset -ga CO_GLOB CO_GLOB_RULE

codeowners_load() {
  emulate -L zsh
  local file=$1
  CO_PATTERNS=()
  CO_OWNERS=()
  CO_GLOB=()
  CO_GLOB_RULE=()
  [[ -r $file ]] || return 0

  local line pattern owners g
  local -a fields
  while IFS= read -r line; do
    line=${line%%\#*}                 # strip trailing comments
    fields=(${=line})                 # split on whitespace
    (( ${#fields} )) || continue
    pattern=${fields[1]}
    owners="${fields[2,-1]}"
    CO_PATTERNS+=("$pattern")
    CO_OWNERS+=("$owners")
    for g in ${(f)"$(_co_glob $pattern)"}; do
      CO_GLOB+=("$g")
      CO_GLOB_RULE+=(${#CO_PATTERNS})
    done
  done < $file
}

# ---------------------------------------------------------------------------
# _co_glob <codeowners-pattern>  ->  prints candidate zsh glob patterns, one
# per line. Translates gitignore syntax into zsh extended globs.
# ---------------------------------------------------------------------------
_co_glob() {
  emulate -L zsh
  local p=$1
  local dironly=0 anchored=0

  [[ $p == */ ]] && { dironly=1; p=${p%/} }
  [[ $p == /* ]] && { anchored=1; p=${p#/} }
  # A separator anywhere but the end anchors the pattern to the repo root.
  [[ $p == */* ]] && anchored=1

  # Escape every character zsh treats as special, so literals stay literal.
  # `*` and `?` are deliberately left alone; they are translated below.
  local g=$p ch
  g=${g//\\/\\\\}
  for ch in '[' ']' '(' ')' '|' '^' '~' '#' '<' '>' '{' '}'; do
    g=${g//$ch/\\$ch}
  done

  # `**` crosses separators; a single `*` must not.
  g=${g//\*\*/$'\002'}
  g=${g//\*/[^\/]\#}
  g=${g//$'\002'/*}
  g=${g//\?/[^\/]}

  # Does the rule extend to everything nested beneath what it names?
  #
  # CODEOWNERS DIVERGES FROM GITIGNORE HERE. Under gitignore, `/docs/*` ignores
  # the direct child directory `docs/build`, and ignoring a directory is
  # recursive, so `docs/build/c.md` is ignored too. GitHub CODEOWNERS does not
  # do that. Its docs are explicit: "The `docs/*` pattern will match files like
  # `docs/getting-started.md` but not further nested files like
  # `docs/build-app/troubleshooting.md`."
  #
  # Getting this wrong is not academic: rule #1 of this repo's CODEOWNERS is
  # `/frontend/* @acme-org/platform-team`. Treating it as
  # recursive hands platform-team every frontend file in the monorepo and puts a
  # team on the report that GitHub never asked to review.
  local last=${p##*/}
  local -i recurse=1
  if [[ $last == '**' ]]; then
    recurse=1                       # `**` is recursive by definition
  elif [[ $last == *[*?]* ]]; then
    recurse=0                       # trailing wildcard segment: direct children only
  fi

  (( dironly )) || print -r -- "$g"
  (( recurse )) && print -r -- "$g/*"
  if (( ! anchored )); then
    (( dironly )) || print -r -- "*/$g"
    (( recurse )) && print -r -- "*/$g/*"
  fi
}

# ---------------------------------------------------------------------------
# codeowners_for <path>  ->  prints the winning rule's owners, space separated.
#   Empty output means no owner: either nothing matched, or the last matching
#   rule was owner-less (GitHub's "remove ownership" idiom).
#   Iterates in reverse so the first hit IS the last matching rule.
# ---------------------------------------------------------------------------
codeowners_for() {
  emulate -L zsh
  setopt extended_glob

  local f=$1
  local -i j
  # Walk the precomputed globs in reverse. Rules were appended in file order, so
  # the first hit belongs to the last matching rule -- GitHub's precedence.
  for (( j = ${#CO_GLOB}; j >= 1; j-- )); do
    if [[ $f == ${~CO_GLOB[j]} ]]; then
      print -r -- "${CO_OWNERS[${CO_GLOB_RULE[j]}]}"
      return 0
    fi
  done
  print -r -- ""
}
