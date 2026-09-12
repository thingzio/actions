# Releasing

Releases are cut by pushing a semver tag. Everything after that is automated.

This document is for maintainers. Contributors do not need it — see
[CONTRIBUTING.md](CONTRIBUTING.md).

## Cutting a release

```shell
git switch main && git pull
git tag -s v1.2.3 -m "v1.2.3"
git push origin v1.2.3
```

Tags are signed because the `main` ruleset requires signed commits, and a
release tag is what other repositories pin their build pipeline to.

There is no local bump tooling here on purpose. The checks that matter are
enforced by `release.yaml` on the server, where they cannot be skipped with an
environment variable, and two of them — "is this commit on `main`" and "did the
selftest pass for this exact commit" — are questions only the server can answer
honestly.

## What happens on the tag

`.github/workflows/release.yaml` runs on any tag matching `v*.*.*`:

1. **Validate the tag.** It must match `vMAJOR.MINOR.PATCH[-prerelease]`. A tag
   that does not is a mistake, not a release.
2. **Require the commit to be on `main`.** A release cut from a side branch
   could point the floating major tag at a build definition nobody reviewed.
   This is the check that matters most, because the floating tag is what a large
   number of repositories build with tomorrow.
3. **Require a green selftest for that exact commit.** `selftest.yaml` is the
   only evidence these workflows actually build and attest — linting proves they
   parse. Releasing without it ships an unproven build definition to every
   repository in the organization, so this fails the release rather than warning
   about it.
4. **Create the release** with generated notes, marked as a prerelease when the
   tag carries one.
5. **Move the floating major tag** to the released commit, through the GitHub
   API rather than `git push --force`, so the job never needs persisted git
   credentials on disk.

A prerelease stops after step 4. `v1.2.3-rc.1` does not move `v1`, for the same
reason a prerelease image never claims `latest`: the floating pointer must never
resolve to something not yet considered releasable.

To re-run for an existing tag, use the `workflow_dispatch` entry point with the
tag name. Creating a release that already exists is a no-op, so a re-run is
safe.

## Versioning

[Semantic versioning](https://semver.org), with one addition specific to this
repository.

**Renaming or moving a reusable workflow file is a major change** even when
every input is unchanged. The filename appears in the Sigstore certificate
identity that consumers verify against, so a rename breaks every existing
`--signer-workflow` and `--certificate-identity-regexp` in the organization.

| Change | Bump |
|---|---|
| Removing or renaming an input, output, or workflow file | major |
| Changing a default in a way that alters what is published | major |
| Tightening validation so a previously accepted input is rejected | major |
| New workflow, new optional input, new output | minor |
| Bug fix, pinned tool version bump, documentation | patch |

Consumers are told to pin by commit SHA, so a minor or patch release reaches
them as a Dependabot or Renovate pull request. Consumers on `@vN` get it
immediately and without review — which is the trade-off that tag exists to
offer, and the reason a breaking change must never ship as a minor.

## Tag protection

A ruleset makes `v*.*.*` tags immutable: creation is allowed, update and
deletion are blocked. A published version can never come to mean different
bytes.

The floating `v1` tag does not match that pattern — one dot, not two — so it
stays movable by the release workflow without needing an exclusion.

## If a release goes wrong

**The tag exists but the workflow failed.** Fix the problem on `main`, then cut
a new patch version. Do not delete and re-push the tag — someone may already
have consumed it, and the tag ruleset blocks it anyway. Version numbers are
free.

**A released version has a serious defect.** Cut a new patch release and move
the floating major tag onto it, which it does automatically. If the defect is a
security issue, request a GitHub advisory as well, so consumers pinned by SHA
find out through their security alerts rather than by reading release notes.

**The floating major tag points at the wrong commit.** Re-run `release.yaml`
with `workflow_dispatch` against the correct tag; it re-points the major tag
idempotently.

## Deprecating a workflow

1. Announce it in the release notes and in the workflow's own header comment,
   naming the replacement.
2. Keep it working for at least one minor release.
3. Add a `::warning::` to its first job, so existing users see it in their own
   run logs rather than only in a changelog they do not read.
4. Remove it in the next major.

## Release checklist

Nothing here is enforced by tooling, which is why it is written down:

- [ ] Anything user-visible is reflected in the README input and output tables
- [ ] A breaking change leads the release notes, with the migration step spelled
      out, and issues are opened on the consuming repositories rather than
      waiting for them to discover it
- [ ] A new or changed workflow is covered by `selftest.yaml`
- [ ] `docs/verification.md` still matches what the workflows actually produce

The tag format, the ancestry check, and the selftest requirement are enforced by
`release.yaml` and are deliberately absent from this list. A checklist item that
tooling already guarantees is an item people stop reading.
