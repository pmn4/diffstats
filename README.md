# diffstats

Three zsh commands that summarise a git diff by **what changed** and **who owns it**.

They exist to answer one question for a reviewer: *GitHub says my team is a
required reviewer on this PR — how much of it is actually mine?*

| Command | Answers |
| --- | --- |
| `diffstats` | How much of this diff is code, tests, support, generated? (`--json` for a data mode) |
| `teamdiffstats` | How many lines does each owning team have? |
| `teamdifffiles` | Which specific files does each owning team have? |

All three take `[from_ref] [to_ref]`, defaulting to `origin/main` and the staged
tree. They must run from the repository root, because ownership is read from
`./.github/CODEOWNERS`.

```console
$ diffstats origin/main HEAD
• Code            █████▒ ( +565, -1)
• Tests              ██  ( +280,  0)
• Support             █  ( +113,  0)
• Generated  ██████████  (+1158,  0)

$ teamdiffstats origin/main HEAD
Team                    Code       Tests      Support
----------------------  ---------- ---------- ----------
acme-org/team-alpha     (+414,  0) (+274,  0) ( +97,  0)
(unowned)               (+151, -1) (  +6,  0) ( +16,  0)
----------------------  ---------- ---------- ----------
TOTAL (each line once)  (+565, -1) (+280,  0) (+113,  0)
```

## Data mode

`diffstats --json` prints the same numbers as a contract another program can
consume, so a downstream tool does not have to re-implement the classifier to
get the same answer:

```console
$ diffstats --json origin/main HEAD
{
  "code": { "files": 2, "additions": 60, "deletions": 0 },
  "test": { "files": 1, "additions": 40, "deletions": 0 },
  "support": { "files": 1, "additions": 87, "deletions": 0 },
  "generated": { "files": 0, "additions": 0, "deletions": 0 }
}
```

Scraping the bar chart instead does not work, and the difference matters: the
bars carry no per-class **file** count, and their column widths move with the
data. A consumer that gates on "how many production files does this touch"
cannot get that number from the rendered output.

Three properties the tests pin, because a parser depends on them:

- **An empty diff still emits a complete object**, all zeros. Only the bar mode
  goes silent, because the commit hook treats empty output as "skip the block".
- **Binary files count toward `files` but contribute no lines.** A reviewer
  still has to open one.
- **`--json` is the only flag**, accepted in any position. Everything else is
  positional, because `--staged` and `--cached` are legitimate refs.

## The ownership model

`lib/changestats.zsh` reproduces GitHub CODEOWNERS semantics, so the team rows
equal the required-reviewer list GitHub shows on the PR:

- **Last matching rule wins.** Not the deepest, not the first.
- **Every owner on the winning rule is credited.** A rule can name several teams.
- **A rule with a pattern but no owners removes ownership** for those paths.
  That is GitHub's documented idiom, and those files land in `(unowned)`.
- **Patterns use gitignore syntax** — path-component matching, not prefix
  matching. `/libs/Form` does not match `/libs/FormWizard/x.ts`.
- **A trailing wildcard segment is NOT recursive.** This is the one place
  CODEOWNERS deliberately diverges from gitignore: `docs/*` matches
  `docs/getting-started.md` but not `docs/build-app/troubleshooting.md`.

A file with several owners is counted in full for each of them, because each one
is separately on the hook for reviewing it. Team rows therefore overlap and can
sum to more than `TOTAL`, which counts each line exactly once and reconciles
with `git diff --numstat`.

## Verifying it

```console
$ zsh lib/changestats-test.zsh
PASS=341 FAIL=0
```

341 assertions covering classification, pattern translation, precedence, and the
`--json` contract.
252 of them are differential tests against `git check-ignore`, which implements
gitignore matching natively and serves as an independent oracle — scoped to
patterns without a trailing wildcard, where the two standards agree.

That oracle is necessary but not sufficient. It passed with zero disagreements
while the matcher still treated `docs/*` as recursive, because git is *correct*
to do that for gitignore. Only comparison against live GitHub caught it:

```console
$ DIFFSTATS_VALIDATE_REPO=owner/name zsh lib/validate-teamdiffstats.zsh 1234 1235
```

This resolves owners for real PRs and diffs the result against the teams GitHub
actually requested, taken from the timeline rather than the current review
state — a team drops out of `reviewRequests` as soon as one of its members
reviews.

Two caveats when reading its output. Bot reviewers requested by automation are
not code owners and are filtered. And a human can request a team manually, which
looks identical in the API to an ownership-driven request — check the event actor
and timestamp before treating a difference as a bug.

`lib/trace-owners.zsh <codeowners-file> <path>...` prints every rule that
matches a path, in file order, so the last line shown is the winner. Use it when
a single file's attribution is surprising.

## Installing

Symlink the three commands onto `PATH`. They locate the library with
`${0:A:h}/lib`, and `:A` resolves symlinks, so linking works:

```sh
for s in diffstats teamdiffstats teamdifffiles; do
  ln -s "$PWD/$s" ~/bin/$s
done
```

To stamp the output into every commit message, call them from a
`prepare-commit-msg` hook. Both commands print nothing when the diff is empty,
so a hook can treat empty output as "skip the stats block".

## Classification

`classify_path` sorts each file into one of four classes. Priority is
`generated` > `support` > `test` > `code`, and `code` is the fallback: an
unrecognised path is treated as something a human must read line by line.

| Class | Means | Signals |
| --- | --- | --- |
| `generated` | Machine-emitted. Nobody authored it, nobody reviews it. | `generated/` and `cassettes/` components, `*.snap` |
| `support` | Scaffolding a reviewer skims for intent. | `.storybook/` and `__mocks__/` components, `*.stories.*`, `*.mock.*`, `locale(s)/**.json`, `*.po`, `*.pot`, `CODEOWNERS`, `product_area(s).yml` |
| `test` | Assertions about behaviour. | `tests/`, `test/`, `__tests__/`, `__test__/`, `cypress/` components; `conftest.py`, `test_*.py`, `*_test.py`; `*.test.*`, `*.spec.*`, `*.cy.*` |
| `code` | Production surface. | Everything else |

The rules are deliberately explicit rather than clever, because the convention
differs per repository — one repo used `.test.*` exclusively, another `.spec.*`
exclusively.

Extension lists are explicit so that build configuration such as
`tsconfig.spec.json` and `vitest.config.ts` stays code. Note for future edits:
zsh's `?` is any-single-char, **not** an optional quantifier — write `ts(x|)` or
`(ts|tsx)`, never `ts(x)?`.

### Why `support` is separate

A reviewer does read a test, to judge whether the coverage is any good. A
reviewer skims a Storybook story. Both are non-production, so the old two-way
split put them together and let one drown out the other.

The cost of that is measurable. On one real PR whose production change was two
files, a single 87-line `*.stories.tsx` was enough to carry the diff from 175
credited lines to 262 — across a 250-line "high complexity" threshold in a
downstream review-time estimator. Storybook, i18n catalogues and ownership
metadata all share that shape: high line count, near-zero reading cost.

Two cheaper options were considered and rejected. Folding them into `test`
makes a two-test PR report six test files, and reads i18n and `CODEOWNERS` as
tests. Folding them into `generated` claims nobody wrote them, when a
hand-written story can be wrong.

`support` beats `test` in priority because `Button.stories.tsx` sits next to
`Button.test.tsx` under one `__tests__/` directory in some layouts. `generated`
beats `support` because a machine-written snapshot can also match a support
pattern, and it belongs in the cheapest bucket.

`teamdiffstats` gives `support` its own credited column rather than dropping it
the way it drops `generated`: a human wrote it and the owning team is still on
the hook, but a team whose whole share is scaffolding has a much smaller reading
job than its line count suggests.

### Overrides

These exist because a name-based heuristic cannot see intent:

| Pattern | Class | Why |
| --- | --- | --- |
| `**/test_data/` | code | A production seeding surface, not a test |
| `send_test_*`, `create_test_*`, `delete_test_*`, `seed_test_*` | code | Production entry points that send test payloads |
| `factories/` | code | Test-data factories are test support, but production factories share the name |
| `migrations/` | code | Mostly autogenerated, but exactly the thing a reviewer must read carefully |

These are judgement calls, and they are a handful of `case` arms in one function
if you disagree.

## License

MIT — see [LICENSE](LICENSE).

## History

The first commit imports the scripts as they ran for nine months, so
`git log -p` shows what was wrong with them. Briefly: the code/test classifier
had been copy-pasted between scripts and drifted, picking up awk's regex
delimiter as a literal and losing its backslashes to zsh quoting, so `\.cy\.`
degraded to `.cy.` with any-char wildcards and matched `billing_cycle`,
`privacy`, `legacy` and `latest_`. Ownership took only the first owner on each
rule, skipped rules that did not start with `/`, matched by prefix, and resolved
by directory depth instead of file order. Owner-less rules produced a
blank-named bucket whose lines silently vanished, so the two tables in a commit
message did not add up.
