#!/bin/zsh
# changestats-test.zsh — self-test for changestats.zsh and the diffstats data mode
#
# Three layers:
#   1. Table-driven unit assertions for classify_path and the glob translator.
#   2. A differential test of the glob translator against `git check-ignore`,
#      which implements gitignore pattern matching natively. CODEOWNERS uses
#      gitignore syntax, so git is a credible independent oracle.
#   3. End-to-end assertions on `diffstats --json` against a real repository.
#      That output is a contract another program parses, so it is pinned here
#      rather than left to whatever the awk happens to print.

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
  # --- generated: lockfiles and build output ---
  # A dependency bump rewrites thousands of lines nobody reads.
  "pnpm-lock.yaml|generated"
  "frontend/pnpm-lock.yaml|generated"
  "package-lock.json|generated"
  "yarn.lock|generated"
  "Gemfile.lock|generated"
  "poetry.lock|generated"
  "Cargo.lock|generated"
  "composer.lock|generated"
  "dist/index.js|generated"
  "frontend/libs/x/dist/index.js|generated"
  "build/main.css|generated"
  "out/server.js|generated"
  "coverage/lcov.info|generated"
  "src/__generated__/schema.ts|generated"
  "src/api.gen.ts|generated"
  "src/api.generated.ts|generated"
  "static/app.min.js|generated"
  "static/app.min.css|generated"
  "proto/service.pb.go|generated"
  "proto/service_pb2.py|generated"
  "lib/models.g.dart|generated"
  # Not generated: a lockfile-adjacent name that a human maintains.
  "packages/x/package.json|code"
  "src/generator.ts|code"
  "src/rebuild.ts|code"
  # --- test: conventions beyond Python/JS ---
  "e2e/checkout.ts|test"
  "frontend/e2e/login.ts|test"
  "spec/models/user_spec.rb|test"
  "internal/server/handler_test.go|test"
  "app/models/user_test.rb|test"
  "app/domains/x/fixtures/payload.json|test"
  "app/domains/x/fixture/payload.json|test"
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
print -r -- "== diffstats --json (end-to-end) =="
# The data mode is a contract a downstream tool parses, so it is asserted
# against a real repository rather than by unit-testing the awk.
ds=${0:A:h:h}/diffstats
json_repo=$(mktemp -d "${TMPDIR:-/tmp}/changestats-json-$$-XXXXXX")
(
  cd $json_repo
  git init -q -b main
  print -r -- seed > seed.txt
  git add -A
  git -c user.email=t@t -c user.name=t commit -qm init
) >/dev/null 2>&1

# An empty diff must still produce a complete object: a consumer parsing "" breaks.
check "json empty diff" \
  '{ "code": { "files": 0, "additions": 0, "deletions": 0 }, "test": { "files": 0, "additions": 0, "deletions": 0 }, "support": { "files": 0, "additions": 0, "deletions": 0 }, "generated": { "files": 0, "additions": 0, "deletions": 0 }}' \
  "$(cd $json_repo && $ds --json main --staged | tr -d '\n' | tr -s ' ')"
# The bar mode must stay silent on an empty diff: the prepare-commit-msg hook
# treats empty output as "skip the stats block".
check "bars empty diff" "" "$(cd $json_repo && $ds main --staged)"

(
  cd $json_repo
  mkdir -p tests
  seq 1 60 > Widget.tsx
  seq 1 87 > Widget.stories.tsx
  seq 1 40 > tests/x.py
  # Binary: counted as a file, contributes no lines.
  printf '\x89PNG\r\n\x1a\n\x00BIN\x00' > logo.png
  git add -A
) >/dev/null 2>&1

check "json populated" \
  '{ "code": { "files": 2, "additions": 60, "deletions": 0 }, "test": { "files": 1, "additions": 40, "deletions": 0 }, "support": { "files": 1, "additions": 87, "deletions": 0 }, "generated": { "files": 0, "additions": 0, "deletions": 0 }}' \
  "$(cd $json_repo && $ds --json main --staged | tr -d '\n' | tr -s ' ')"

# `--staged` and `--cached` are real refs, so only `--json` may be read as a
# flag. It must be accepted in any position.
a=$(cd $json_repo && $ds --json main --staged)
b=$(cd $json_repo && $ds main --staged --json)
c=$(cd $json_repo && $ds main --json --staged)
check "json flag position (trailing)" "$a" "$b"
check "json flag position (infix)"    "$a" "$c"

rm -rf $json_repo

# --------------------------------------------------------------------------
print -r -- ""
print -r -- "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
