# Contributing to actions

Contributions are welcome, from typo fixes to new workflows. This document
covers what you need to know before opening a pull request.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Project governance](#project-governance)
- [Developer Certificate of Origin](#developer-certificate-of-origin)
- [Getting started](#getting-started)
- [How to contribute](#how-to-contribute)
- [Pull request process](#pull-request-process)
- [Code style](#code-style)
- [Getting help](#getting-help)

## Code of Conduct

Be respectful and professional. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Project governance

This is a single-maintainer project. Decisions — what gets merged, what ships,
what is in scope — are the maintainer's, and the maintainer is listed in
[MAINTAINERS.md](MAINTAINERS.md). There is no steering committee and no vote,
because there are not enough people for either to mean anything.

**There is no review-time commitment.** A pull request may be reviewed the same
day or may sit for weeks. The project is maintained on a best-effort basis, and
pretending otherwise would set an expectation that gets broken. If something is
urgent for you, say so in the pull request — it helps with ordering, though it
is not a guarantee.

What this means in practice:

- **Small, focused pull requests get reviewed fastest.** A change touching both
  a workflow and the documentation around it is fine; a change touching both
  workflows and the test harness is two pull requests.
- **Open an issue before a large change.** Finding out that a direction is wrong
  after a week of work is worse for you than for the project.
- **A closed pull request is not a judgment on you.** Scope is the most common
  reason.

Adding a second maintainer is described in [MAINTAINERS.md](MAINTAINERS.md).
Short version: sustained, substantive contribution plus a willingness to take
the responsibility.

## Developer Certificate of Origin

This project requires the [Developer Certificate of
Origin](https://developercertificate.org) (DCO). It is not a CLA — you keep your
copyright, and you are not assigning anything. You are certifying that you wrote
the contribution or otherwise have the right to submit it under the project's
license.

Certify it by adding a `Signed-off-by` trailer to every commit:

```shell
git commit -s -m "feat: add the thing"
```

## Getting started

You need `bash`, `curl`, `jq`, `python3`, `make`, and `shellcheck`
(`brew install shellcheck`, or `apt-get install shellcheck`; GitHub runners have
it preinstalled). **You do not need any credentials from the maintainer, and you
do not need a registry account.** If you hit a step that seems to require
either, that is a bug — please file it.

```shell
git clone https://github.com/thingzio/actions && cd actions
make verify         # the full gate CI runs
make test           # the shell test suite
make test-offline   # same, skipping tests that reach the network
make lint           # actionlint, yamllint, shellcheck
make versions       # print every pinned version
```

Everything else installs itself into `.bin/` at the versions pinned in
`.versions.yaml`, so a laptop and a runner lint with the same binaries. If
`make verify` passes locally it should pass in CI; if it does not, that is worth
an issue.

Run a single suite or a single test:

```shell
./test/run.sh derive-tags    # one suite
./test/run.sh '' rejects     # tests whose name contains "rejects"
```

See [docs/slsa.md](docs/slsa.md) for the security argument the design rests on,
and [docs/verification.md](docs/verification.md) for the consumer contract.

## How to contribute

### Reporting bugs

> **Security vulnerabilities do not go here.** Report them privately through
> [GitHub Security Advisories](https://github.com/thingzio/actions/security/advisories/new).
> See [SECURITY.md](SECURITY.md) for scope and expected response times.

Open an [issue](https://github.com/thingzio/actions/issues/new/choose) and use
the bug template. The most useful bug report contains the smallest reproduction
you can manage — a failing test is ideal, a link to a failed workflow run is
good, a description of the behavior is workable.

### Suggesting enhancements

Use the feature template. Lead with the problem you are trying to solve rather
than the solution you have in mind; the problem statement is the part most
likely to change the design.

### Improving documentation

Always welcome and always in scope. Documentation fixes are the best way to make
a first contribution — if something was confusing to you, it was confusing to
someone else, and you are the person best placed to fix it right now.

### Contributing code

Read the surrounding code first and match it. Consistency with what is already
there beats an individually better pattern applied in one place.

Where things live:

| Kind of change | Where |
|---|---|
| Logic worth testing — validation, parsing, derivation | `scripts/*.sh`, tests in `test/*_test.sh` |
| The body of a composite action | `scripts/actions/*.sh`, called from a one-line `run:` |
| A composite action's interface | `.github/actions/<name>/action.yml` |
| A reusable workflow | `.github/workflows/<name>.yaml` |

Shell embedded in an `action.yml` is linted by nothing — actionlint checks
workflows but not composite actions, and a glob over `.sh` files cannot reach
inside YAML. That is why action bodies live in `scripts/actions/`. Keep the
`run:` block to a single invocation.

#### The reusable workflows are a trust boundary

`build-ko.yaml` and `build-docker.yaml` are trusted build definitions. Their
SLSA Build Level 3 claim rests on a caller being unable to alter what runs in
them, and the following rules exist to keep that true. A pull request that
breaks one will be declined regardless of how useful it is.

1. **No input may become shell.** No `build_command`, `pre_build_script`,
   `post_steps`, or any input reaching `eval`, `bash -c`, or a `run:` body. Each
   is an arbitrary-code-execution primitive inside the trusted builder, running
   beside the OIDC token. If a caller needs a new knob, add a specific,
   validated input for it.
2. **`runs-on` is never caller-controlled.** Runner labels come from the closed
   allowlist in `scripts/validate-inputs.sh`.
3. **Caller data reaches shell only through `env:`.** Never `${{ inputs.foo }}`
   inside a `run:` body — that is substitution before the shell sees it, and a
   tag named `$(id)` becomes a command.
4. **Every `uses:` is pinned to a commit SHA** with a trailing `# vX.Y.Z`
   comment.
5. **No `pull_request_target`.** Not with a fork checkout, not without one.
6. **No `curl | bash`.** Binaries come through `scripts/install-tool.sh`, which
   verifies a published checksum and fails closed.

Renaming a reusable workflow file is a **breaking change** even when its inputs
are unchanged: the filename appears in the certificate identity consumers verify
against.

#### Tests

The harness is plain bash, not bats. That is deliberate: this repository's
subject is supply-chain hygiene, and bats ships as a GitHub-generated source
tarball with no stable checksum to pin. A test dependency we could not hold to
our own standard would undercut the point. `test/run.sh` is sixty lines and
`test/lib/assert.sh` documents every assertion.

A test file is `test/<name>_test.sh` containing only function definitions. Any
function named `test_*` is a test; it passes by returning zero.

```shell
test_rejects_a_tag_containing_a_slash() {
  run bash "${REPO_ROOT}/scripts/derive-tags.sh" release
  assert_failed
  assert_stderr_contains "is not a valid OCI tag"
}
```

Use `run` for anything that might exit — scripts call `die()`, which exits, and
a bare invocation would take the test process with it.

Write the test first and watch it fail before fixing anything; a test that has
never failed has not been shown to test anything. Cover the failure the change
exists to prevent, not just the happy path. Most tests here assert on rejection,
because for a build pipeline the dangerous outcome is almost always "accepted
something it should not have".

#### Changing a workflow

Anything that alters what gets built or signed must be observable in
`selftest.yaml`, which builds the fixtures in `testdata/` for real and verifies
the resulting attestations. If your change is not observable there, add a case
that makes it observable. Linting proves a workflow parses; only the selftest
proves it works.

Bumping a tool version is a one-line edit to `.versions.yaml` — nothing else
hardcodes a version, and the selftest proves the bump before it merges.

## Pull request process

1. **Make `make verify` pass.** Shell tests, actionlint, yamllint, shellcheck.
2. **Update documentation** if you changed behavior someone depends on.
3. **Sign off your commits** — see
   [Developer Certificate of Origin](#developer-certificate-of-origin).
4. **Open the pull request against `main`** with a clear summary. Reference
   related issues (`Fixes #123`).

Automated checks run on every pull request. If a check fails on your first
contribution and the failure looks unrelated to your change, say so in the pull
request rather than assuming it is your fault — it may well be ours.

Pull requests from forks build the fixtures but do not publish, sign, or attest
them, because a fork has no write credential and no OIDC token. That is
expected, and the job summary says so.

Review covers correctness, test coverage, and consistency with existing
patterns. Address feedback by pushing new commits rather than force-pushing, so
the conversation stays readable; squashing happens at merge.

## Code style

- `set -euo pipefail` at the top of every script
- Bash 3.2 compatible — no `mapfile`, no `declare -A`, no `${var,,}`. macOS
  ships bash 3.2, and "local development equals CI" is only true if the same
  script runs in both places
- Quote every expansion; validate at the boundary and never re-validate on trust
- Fail with `die`, which writes a GitHub `::error::` and exits, rather than
  returning a sentinel nobody checks
- Guard `main` behind `[ "${BASH_SOURCE[0]}" = "${0}" ]` so a script can be
  sourced by tests
- Comments explain *why*. What the line does is visible; the reason it is
  written that way usually is not, and in this repository the reason is often
  the point

Commit messages follow [Conventional
Commits](https://www.conventionalcommits.org): `feat:`, `fix:`, `docs:`,
`refactor:`, `test:`, `chore:`. The subject line says what changed; the body
says why.

## Getting help

Open an [issue](https://github.com/thingzio/actions/issues/new/choose) with the
question label. Search existing issues first.
