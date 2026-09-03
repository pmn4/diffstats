#!/bin/zsh
# changestats-test.zsh — self-test for changestats.zsh
#
# Two layers:
#   1. Table-driven unit assertions for classify_path and the glob translator.
#   2. A differential test of the glob translator against `git check-ignore`,
#      which implements gitignore pattern matching natively. CODEOWNERS uses
#      gitignore syntax, so git is a credible independent oracle.

emulate -L zsh
setopt extended_glob

source ${0:h}/changestats.zsh

typeset -i PASS=0 FAIL=0

ok()   { (( PASS++ )); }
bad()  { (( FAIL++ )); print -r -- "  FAIL: $1"; }

check() {  # check <desc> <expected> <actual>
  if [[ $2 == $3 ]]; then ok; else bad "$1 — expected [$2] got [$3]"; fi
}

# --------------------------------------------------------------------------
print -r -- "== classify_path =="
# path                                                          expected
typeset -a cases=(
  "app/domains/billing_cycle/models/claim.py|code"
  "app/domains/messaging/privacy_mode_handler.py|code"
  "app/domains/observe/legacy_report.py|code"
  "app/domains/provider/tasks/process_provider_latest_login_event.py|code"
  "app/domains/feature_alpha/tests/test_feature_alpha_repos.py|test"
  "app/domains/feature_alpha/tests/__init__.py|test"
  "tests/app/mediators/test_delete_test_data_proxy.py|test"
  "conftest.py|test"
  "app/x/conftest.py|test"
  "app/domains/circuit_breaker/scripts/circuit_breaker_test.py|test"
  "frontend/libs/foo/Bar.test.tsx|test"
  "frontend/libs/foo/Bar.cy.ts|test"
  "frontend/eslint/vitest.config.ts|code"
  "frontend/libs/x/tsconfig.spec.json|code"
  "src/worker/dispatch.spec.ts|test"
  "src/phases/pr_open/glance-input.spec.ts|test"
  "src/adapters/chassis/foo.spec.tsx|test"
  "packages/x/jest.spec.json|code"
  "app/mediators/test_data/delete_providers.py|code"
  "app/domains/test_data/services/insurance_test_data.py|code"
  "app/domains/notifications/services/send_test_email_service.py|code"
  "cassettes/app.domains.foo/TestFoo.test_copay.yaml|generated"
  "generated/schema.ts|generated"
  "frontend/libs/x/__snapshots__/a.snap|generated"
  "migrations/versions/c9a1f4b83d27_create_feature_alpha_pilot_tables.py|code"
  "app/domains/feature_alpha/factories/feature_alpha_day.py|code"
  "cypress/e2e/login.cy.ts|test"
  "app/domains/marketplace/tests/fixtures.py|test"
  # --- support ---
  "frontend/libs/foo/Bar.stories.tsx|support"
  "frontend/libs/foo/Bar.stories.mdx|support"
  "frontend/.storybook/main.ts|support"
  "frontend/libs/foo/__mocks__/api.ts|support"
  "frontend/libs/foo/api.mock.ts|support"
  "frontend/libs/i18n/src/locales/en/core.json|support"
  "locale/de.json|support"
  "translations/messages.po|support"
  "translations/messages.pot|support"
  ".github/CODEOWNERS|support"
  "CODEOWNERS|support"
  "product_areas.yml|support"
  "app/domains/feature_alpha/product_area.yml|support"
  # `support` beats `test`: a story under a tests/ component is still a story,
  # and a hand-written double is scaffolding rather than an assertion.
  "frontend/libs/foo/__tests__/Bar.stories.tsx|support"
  "tests/frontend/__mocks__/api.ts|support"
  # `generated` still beats `support`.
  "generated/Bar.stories.tsx|generated"
  # Support patterns are extension-scoped for the same reason the test ones are:
  # a `.storybook`-adjacent name must not swallow production code.
  "frontend/libs/foo/stories.ts|code"
  "frontend/libs/foo/Bar.stories.json|code"
  "frontend/libs/i18n/src/locales/en/core.ts|code"
  "app/domains/foo/mock.py|code"
  "app/domains/foo/product_area_registry.py|code"
)
for c in $cases; do
  local p=${c%%|*} want=${c##*|}
  check "$p" "$want" "$(classify_path $p)"
done

# --------------------------------------------------------------------------
print -r -- "== glob translation (unit) =="
# Returns 0 when any candidate glob matches.
co_match() {  # co_match <file> <pattern>
  local f=$1 g
  for g in ${(f)"$(_co_glob $2)"}; do
    [[ $f == ${~g} ]] && return 0
  done
  return 1
}

expect_match()   { if co_match "$1" "$2"; then ok; else bad "'$2' should match '$1'"; fi }
expect_nomatch() { if co_match "$1" "$2"; then bad "'$2' should NOT match '$1'"; else ok; fi }

# Prefix-vs-component matching: the bug that mis-credited FormWizard.
expect_match   "libs/core/src/Form"                "/libs/core/src/Form"
expect_match   "libs/core/src/Form/Input.tsx"      "/libs/core/src/Form"
expect_nomatch "libs/core/src/FormWizard/Step.tsx" "/libs/core/src/Form"
expect_nomatch "libs/core/src/FormWizard"          "/libs/core/src/Form"

# Directory rules.
expect_match   "migrations/versions/a.py"          "/migrations/"
expect_match   "migrations/a.py"                   "/migrations/"
expect_nomatch "app/migrations/a.py"               "/migrations/"

# Unanchored rules match at any level.
expect_match   ".claude/settings.json"             ".claude/"
expect_match   "app/.claude/settings.json"         ".claude/"
expect_match   "CLAUDE.md"                         "CLAUDE.md"
expect_match   "app/domains/x/CLAUDE.md"           "CLAUDE.md"

# Single star must not cross a separator; double star must.
expect_match   "app/foo/models.py"                 "/app/*/models.py"
expect_nomatch "app/foo/bar/models.py"             "/app/*/models.py"
expect_match   "app/foo/bar/models.py"             "/app/**/models.py"
expect_match   "app/foo/models.py"                 "/app/**/models.py"

# Exact file rules.
expect_match   "product_areas.yml"                 "/product_areas.yml"
expect_nomatch "app/product_areas.yml"             "/product_areas.yml"
expect_nomatch "product_areas.yml.bak"             "/product_areas.yml"

# Literal characters that are glob-special must stay literal.
expect_match   "app/(routes)/page.tsx"             "/app/(routes)/"
expect_nomatch "app/routes/page.tsx"               "/app/(routes)/"

# CODEOWNERS-SPECIFIC: a trailing wildcard segment is NOT recursive. This is the
# documented divergence from gitignore, so it is asserted here rather than via
# the git check-ignore oracle below (git would disagree, correctly, for its own
# semantics). GitHub's own example: `docs/*` matches `docs/getting-started.md`
# but not `docs/build-app/troubleshooting.md`.
expect_match   "docs/getting-started.md"           "docs/*"
expect_nomatch "docs/build-app/troubleshooting.md" "docs/*"
expect_match   "frontend/README.md"   "/frontend/*"
expect_nomatch "frontend/libs/i18n/src/locales/en/core.json" "/frontend/*"
# `**` stays recursive.
expect_match   "frontend/libs/i18n/x.json" "/frontend/**"
# A directory rule stays recursive.
expect_match   "frontend/libs/i18n/x.json" "/frontend/"

# --------------------------------------------------------------------------
print -r -- "== glob translation (differential vs git check-ignore) =="
# git check-ignore is an independent implementation of gitignore matching.
oracle_dir=$(mktemp -d "${TMPDIR:-/tmp}/changestats-oracle-$$-XXXXXX")
git -C $oracle_dir init -q 2>/dev/null

typeset -a patterns=(
  "/libs/core/src/Form" "/migrations/" ".claude/" "CLAUDE.md"
  "/app/*/models.py" "/app/**/models.py" "/product_areas.yml"
  "/utils/utils.py" "/frontend/libs/roots/global-root/"
  "/app/domains/observe/" "/.github/workflows/" "*.md"
)
typeset -a probes=(
  "libs/core/src/Form" "libs/core/src/Form/Input.tsx"
  "libs/core/src/FormWizard/Step.tsx" "migrations/versions/a.py"
  "migrations/a.py" "app/migrations/a.py" ".claude/settings.json"
  "app/.claude/settings.json" "CLAUDE.md" "app/domains/x/CLAUDE.md"
  "app/foo/models.py" "app/foo/bar/models.py" "product_areas.yml"
  "app/product_areas.yml" "utils/utils.py" "utils/utils.pyc"
  "frontend/libs/roots/global-root/index.ts"
  "app/domains/observe/product_area_registry.py" ".github/workflows/ci.yml"
  "docs/readme.md" "a/b/c.md"
)

typeset -i diffs=0
for pat in $patterns; do
  print -r -- "$pat" > $oracle_dir/.gitignore
  for probe in $probes; do
    if git -C $oracle_dir check-ignore --no-index -q "$probe" 2>/dev/null; then
      want=match
    else
      want=nomatch
    fi
    if co_match "$probe" "$pat"; then got=match; else got=nomatch; fi
    if [[ $want != $got ]]; then
      (( diffs++ )); (( FAIL++ ))
      print -r -- "  DIFF: pattern '$pat' vs '$probe' — git says $want, we say $got"
    else
      (( PASS++ ))
    fi
  done
done
rm -rf $oracle_dir
print -r -- "  differential cases: $(( ${#patterns} * ${#probes} )), disagreements: $diffs"

# --------------------------------------------------------------------------
print -r -- "== codeowners_for (precedence + multi-owner + owner-less) =="
co_fixture=$(mktemp "${TMPDIR:-/tmp}/changestats-co-$$-XXXXXX")
cat > $co_fixture <<'FIX'
# comment line, must be ignored
/app/ @team-general
/app/domains/ @team-domains @team-second
/app/domains/observe/ @team-observe
/app/domains/observe/legacy.py
/utils/utils.py
/libs/Form @team-form
*.md @team-docs
FIX
codeowners_load $co_fixture

# Last match wins, not deepest and not first.
check "general"        "@team-general"                 "$(codeowners_for app/main.py)"
# All owners on the winning rule are credited.
check "multi-owner"    "@team-domains @team-second"    "$(codeowners_for app/domains/foo/bar.py)"
# A later, more specific rule overrides.
check "more specific"  "@team-observe"                 "$(codeowners_for app/domains/observe/registry.py)"
# Owner-less rule removes ownership (GitHub idiom).
check "ownerless deep" ""                              "$(codeowners_for app/domains/observe/legacy.py)"
check "ownerless root" ""                              "$(codeowners_for utils/utils.py)"
# Component matching, not prefix matching.
check "Form exact"     "@team-form"                    "$(codeowners_for libs/Form/Input.tsx)"
check "FormWizard"     ""                              "$(codeowners_for libs/FormWizard/Step.tsx)"
# Unanchored wildcard rule, last in file, beats earlier anchored rules.
check "md override"    "@team-docs"                    "$(codeowners_for app/domains/observe/README.md)"
# Nothing matches.
check "unmatched"      ""                              "$(codeowners_for scripts/tool.sh)"
rm -f $co_fixture

# --------------------------------------------------------------------------
print -r -- ""
print -r -- "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
