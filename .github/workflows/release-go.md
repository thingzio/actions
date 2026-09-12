# `release-go.yaml`

Releases a Go repository's **binaries** with goreleaser, signs the checksum file
with a keyless Sigstore signature, and attaches **SLSA Build Level 3**
provenance.

The container equivalents are [`build-ko.yaml`](build-ko.md) and
[`build-docker.yaml`](build-docker.md). This is the same supply-chain promise
for artifacts that are not images.

## Why this workflow has three jobs

`build-ko.yaml` builds and attests in one job. This one cannot, and the reason
is worth understanding before changing anything here.

**goreleaser executes code from the calling repository.** A `.goreleaser.yaml`
carries `before.hooks`, `builds.hooks` and `signs.cmd` — all arbitrary shell,
all authored by the caller. ko and buildx execute no caller configuration, so
nothing in those workflows can run beside the OIDC token.

If the token were present while a caller's hook ran, the hook could take it and
mint provenance naming *this* workflow as the builder for bytes this workflow
never produced. That is precisely the forgery Build Level 3 excludes, so the
jobs are split by what each is allowed to touch:

| Job | Permissions | Runs caller code |
|---|---|---|
| `build` | `contents: write` | **yes** — goreleaser and its hooks |
| `attest` | `id-token: write`, `attestations: write`, `contents: write` | no |
| `publish` | `contents: write` | no |

Only `checksums.txt` crosses from `build` into `attest`. It is not trusted for
being a checksum file: it was written by the job that runs the caller's hooks,
and every `(digest, filename)` pair in it becomes a subject of provenance signed
under *this* workflow's identity. So before signing, `attest` downloads the
artifacts actually attached to the release and re-derives each digest. A line
naming a file the release does not carry, or a digest that does not match its
bytes, fails the release before a signature exists.

A compromised build can still produce bad artifacts, and provenance will
faithfully describe them. That is what SLSA promises and what it does not: the
*provenance* is non-forgeable, so an attacker cannot claim a different builder.
Whether the inputs were trustworthy is a different question, answered by
policy.

## Usage

```yaml
name: release

on:
  push:
    tags: ['v*']

permissions:
  contents: read

jobs:
  release:
    permissions:
      contents: write
      id-token: write
      attestations: write
    uses: thingzio/actions/.github/workflows/release-go.yaml@<commit-sha>  # v1.6.0
    secrets:
      homebrew_deploy_key: ${{ secrets.HOMEBREW_DEPLOY_KEY }}
```

**Pin by commit SHA.** A floating tag is a build definition someone can move,
which is the mutable-builder problem Level 3 exists to exclude. See
[SLSA](../../docs/slsa.md).

## What a caller must change

Every requirement below is checked by `scripts/check-goreleaser-config.sh`
before goreleaser is allowed to run, and the build fails naming the one that is
missing. They are all things that otherwise fail silently — green CI, a release
that looks right, and a property lost that only the person trusting it finds
out about.

**Set `release.draft: true`.** The release is created by `build` and signed by
`attest`, so without this there is a live, publicly downloadable release with no
signature and no provenance for the length of the attest job. goreleaser's own
default is `draft: false`, so doing nothing gets the unsafe shape. After
goreleaser runs, `build` also asks the API whether the release is really a
draft, and if it is not, returns it to draft before failing.

**Set `release.use_existing_draft: true`.** GitHub does not return drafts when
looking a release up by tag, so on a re-run goreleaser cannot see the draft it
created last time and opens a second one for the same tag. `attest` and
`publish` then address "the" release by tag with two candidates present.

**Remove any `signs:` block.** Signing happens in the `attest` job, where the
caller cannot reach the identity. The workflow passes `--skip=sign`, so a
`signs` block is ignored rather than honoured — leaving one in place is a
signature you think you have and do not.

**Keep a `checksum:` block.** It is the attestation subject. The build fails
loudly if goreleaser produces no checksum file, rather than publishing a
release nothing covers.

**Add an `sboms:` block** to get SBOMs. The workflow installs syft, but
goreleaser only produces SBOMs when asked:

```yaml
sboms:
  - id: archives
    artifacts: archive
```

Without it the release carries none, and the build says so as a warning rather
than an error — a caller may legitimately not want them.

**Keep `homebrew_casks[].skip_upload` guarded** on the presence of the deploy
key, so a repository without the secret does not attempt a cross-repository
push.

[`testdata/go-app/.goreleaser.yaml`](../../testdata/go-app/.goreleaser.yaml) is
a minimal configuration with all of this in place, and the test suite checks it
against the same script, so it cannot drift from this list.

## Inputs

| Input | Default | Description |
|---|---|---|
| `go_version` | `''` | Explicit Go version. Empty reads `go_version_file`. |
| `go_version_file` | `.go-version` | File the Go version is read from. |
| `working_directory` | `.` | Directory holding `go.mod` and `.goreleaser.yaml`. |
| `goreleaser_version` | `''` | Override the pinned goreleaser version. |
| `syft_version` | `''` | Override the pinned syft version. |
| `cosign_version` | `''` | Override the pinned cosign version. |
| `dry_run` | `false` | Snapshot build; signs, attests and publishes nothing. |

There is deliberately no `args` input. Arbitrary goreleaser flags would be
caller-supplied shell in the build definition, which is the hole the three-job
split exists to close.

## Secrets

| Secret | Required | Description |
|---|---|---|
| `homebrew_deploy_key` | no | Token with `contents: write` on the Homebrew tap. |

## Outputs

| Output | Description |
|---|---|
| `version` | Released version, without the leading `v` |
| `prerelease` | Whether the tag is a prerelease |
| `checksums_digest` | SHA-256 of the signed checksum file |

All three are empty on a `dry_run`, which resolves no tag, signs nothing and
publishes nothing. A caller that consumes them needs to handle that or not run
them on a dry run.

`prerelease` is for the caller's own steps — announcing a release, moving a
floating tag. goreleaser decides its own prerelease behaviour from
`prerelease: auto`, and this output does not feed it.

## When something fails partway

The jobs are ordered so that the expensive, caller-controlled work happens
before anything becomes visible, which means a failure usually leaves a draft
release behind rather than a bad public one.

**`attest` failed.** The draft exists with artifacts on it and nothing signed
it. Nothing is public: `publish` is blocked by `needs:`. Re-run **only the
failed jobs**. `attest` will re-download the release artifacts and re-verify
them against the checksum file it kept from the build, which is retained for
seven days for exactly this. Do not re-run the whole workflow: that is a second
`goreleaser release` against a release that already exists.

**`build` failed after the draft was created.** Re-running is safe because
`release.use_existing_draft: true` makes goreleaser reuse that draft rather than
open a second one. Without that setting it would not, which is why it is
required.

**Everything failed and you want to start over.** Delete the draft release and
the tag, then re-tag. A draft is not immutable; a published release is.

**The Homebrew cask.** goreleaser pushes it during `build`, before anything is
signed. If the release never publishes, the tap points `brew install` at a
draft release that anonymous downloads cannot reach, and the workflow has no
step that reverts it — the tap is a separate repository. Revert that commit by
hand. Guarding the cask on `prerelease: auto` and cutting a release candidate
first is the cheaper way to find this out.

## Verifying a release

One signature covers the whole release, because the checksum file commits to
every artifact by digest:

```bash
gh release download v1.2.3 -p 'checksums.txt' -p 'checksums.txt.bundle'

cosign verify-blob checksums.txt \
  --bundle checksums.txt.bundle \
  --certificate-identity-regexp '^https://github\.com/thingzio/actions/\.github/workflows/release-go\.yaml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

sha256sum --check --ignore-missing checksums.txt
```

Note the identity: the signer is **this workflow**, not the repository being
released. That is the Level 3 property made checkable. The release job asserts
the same thing before publishing, so a release fails rather than shipping a
signature nobody verified.

Build provenance is attested separately and covers every artifact named in the
checksum file:

```bash
gh attestation verify myapp_1.2.3_linux_amd64.tar.gz --repo thingzio/myapp \
  --signer-workflow thingzio/actions/.github/workflows/release-go.yaml
```

`--signer-workflow` is what distinguishes Level 3 from Level 2. Without it the
check passes for provenance signed by any workflow in the repository, including
one an attacker added.

## The release-candidate flow

`prerelease: auto` in `.goreleaser.yaml` plus `skip_upload: auto` on a cask
means a `-rc` tag exercises the whole path without publishing the cask. Useful
before a first release, or any release that changes the pipeline.

Cut the final tag on a **later commit** than its candidate. The workflow states
the triggering tag explicitly via `GORELEASER_CURRENT_TAG`, so two tags on one
commit no longer resolve to the wrong release — but a release and its candidate
describing the same tree is confusing for people, if no longer for tools.
