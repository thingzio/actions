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

Only `checksums.txt` crosses from `build` into `attest`. That file already
commits to every artifact by digest, so the trusted job never handles a binary
the caller's build produced.

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

**Remove any `signs:` block from `.goreleaser.yaml`.** Signing happens in the
`attest` job, where the caller cannot reach the key. The workflow passes
`--skip=sign`, so a `signs` block is ignored rather than honoured — leaving one
in place is a signature you think you have and do not.

**Keep a `checksum:` block.** It is the attestation subject. The build fails
loudly if goreleaser produces no checksum file, rather than publishing a
release nothing covers.

**Set `release.draft: true`.** The release is then invisible until its
signature has been verified, and the `publish` job flips it. A caller who
publishes directly still works; the flip is a no-op.

**Keep `homebrew_casks[].skip_upload` guarded** on the presence of the deploy
key, so a repository without the secret does not attempt a cross-repository
push.

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
