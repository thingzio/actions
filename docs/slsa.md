# SLSA Build Level 3

Artifacts built by `build-ko.yaml`, `build-docker.yaml` and `release-go.yaml`
meet [SLSA v1.0](https://slsa.dev/spec/v1.0/levels) **Build Level 3** — images
for the first two, Go binaries for the third.

This page explains why that is true, what it does and does not promise, and
what would silently drop you back to Level 2.

## Why a reusable workflow is the whole argument

Build Level 3 requires that provenance be **non-forgeable**: the signing
identity must be unavailable to anything the build itself can influence.

GitHub's artifact attestations are **Build Level 2** when
`actions/attest-build-provenance` runs in a workflow you control, because you
can add a step next to the signing step and do whatever you like with the OIDC
token. They reach **Build Level 3** when the build *and* the attestation live in
a reusable workflow, because:

1. The reusable workflow is an immutable build definition. A caller supplies
   inputs and permissions; it cannot add, remove or reorder steps.
2. GitHub-hosted runners are ephemeral and isolated per job.
3. Sigstore records the *reusable* workflow as the signer. Fulcio maps the
   GitHub OIDC `job_workflow_ref` claim — which inside a reusable workflow is
   the reusable workflow, not the caller — to the certificate SAN and to the
   Build Signer URI extension (OID `1.3.6.1.4.1.57264.1.9`).

That third point is what makes the level verifiable rather than merely claimed.
A verifier can require that an image was built by *this* definition:

```bash
gh attestation verify oci://ghcr.io/thingzio/my-app:v1.2.3 \
  --repo thingzio/my-app \
  --signer-workflow thingzio/actions/.github/workflows/build-ko.yaml
```

The same command shape verifies a binary, naming the workflow that built it:

```bash
gh attestation verify my-app_1.2.3_linux_amd64.tar.gz \
  --repo thingzio/my-app \
  --signer-workflow thingzio/actions/.github/workflows/release-go.yaml
```

Dropping `--signer-workflow` is what silently reduces either check to Level 2:
without it, provenance signed by *any* workflow in the repository passes,
including one an attacker added.

For completeness, the other identity extensions Fulcio records:

| Extension | OID | Value |
|---|---|---|
| Build Signer URI | `1.3.6.1.4.1.57264.1.9` | the reusable workflow — the build definition |
| Build Config URI | `1.3.6.1.4.1.57264.1.18` | the caller's workflow — the entry point |
| Source Repository URI | `1.3.6.1.4.1.57264.1.12` | the repository built from |

## What this design gives up to keep the level

Every one of these is a deliberate cost, not an oversight.

**No input may become shell.** There is no `build_command`, `pre_build_script`,
`post_steps` or equivalent, and there never will be. Such an input is an
arbitrary-code-execution primitive inside the trusted builder, running next to
the OIDC token. `ko_flags` exists but is a closed allowlist
(`--image-user=<uid>`, `--image-annotation=<k>=<v>`, `--disable-optimizations`,
`--debug`); an open flag list would let `--platform` bypass the runner
allowlist below.

**You cannot choose the runner.** Platforms map to runner labels through a fixed
allowlist in `scripts/validate-inputs.sh`. A caller-supplied `runs-on` could
name a self-hosted machine the caller controls, and "the build platform is
isolated" would stop being true.

**Only `linux/amd64` and `linux/arm64` are supported.** Adding a platform means
adding a runner mapping, deliberately.

## Why `release-go.yaml` needs three jobs to say the same thing

ko and buildx execute no caller configuration, so `build-ko.yaml` and
`build-docker.yaml` can build and attest in one job. goreleaser does: a
`.goreleaser.yaml` carries `before.hooks`, `builds.hooks` and `signs.cmd`, all
arbitrary shell, all authored by the caller. A caller's hook running beside the
OIDC token could take it and mint provenance naming this workflow as the builder
for bytes this workflow never produced — Level 3's defining forgery.

So `release-go.yaml` splits the work by what each job may touch. `build` runs
goreleaser and its hooks and holds **no** `id-token`. `attest` holds the signing
identity and runs no caller code at all. Only the checksum file crosses between
them, and `attest` re-derives every digest in it from the artifacts actually on
the release before signing, because a file written by the caller's build is not
evidence about the caller's build.

Two consequences worth knowing:

- **There is no `args` input**, for the same reason there is no `build_command`
  in the image workflows. Arbitrary goreleaser flags are caller-supplied shell
  in the build definition.
- **The caller's `.goreleaser.yaml` is checked before goreleaser runs**, because
  several of the properties this page claims depend on it — see
  [`release-go.md`](../.github/workflows/release-go.md).

## What breaks the level

| If you… | Result |
|---|---|
| Call the **composite actions** from your own workflow instead of the reusable workflows | Build Level 2. You control the job, so the isolation argument does not hold. |
| Run the workflows on a self-hosted runner via a fork of this repository | Not Level 3 unless that runner is genuinely ephemeral and isolated. |
| Add an input that reaches a shell | Level 2, silently. This is the failure mode to guard in review. |
| Rename a reusable workflow file | Existing verification commands stop matching — the filename is part of the certificate identity. Treat as a breaking change. |
| Verify without `--signer-workflow` | Level 2 in practice. Any workflow in the repository passes, which is the thing Level 3 exists to distinguish. |
| Give `release-go.yaml`'s `build` job an `id-token` | Level 2, and worse: caller hooks would run beside a signing identity. |

## What Build Level 3 does *not* mean

Worth being precise, because the number is easy to over-read:

- **It is not a statement about the source.** Provenance says "this build
  definition, on this platform, produced these bytes from this commit". It says
  nothing about whether that commit is good. A malicious commit produces a
  perfectly valid Level 3 attestation.
- **It is not a vulnerability claim.** The SBOM lists what is in the image. It
  does not assert anything is unaffected by a CVE.
- **It is not hermetic.** SLSA v1.0 Build L3 requires non-forgeable provenance
  and an isolated build, not a network-isolated one. A `go mod download` or a
  `pip install` still reaches the internet.
- **It does not cover the base image.** Pin base images by digest yourself; a
  mutable base tag means the same source can produce different bytes.

## Reproducibility

Builds are idempotent but not bit-for-bit reproducible. Re-running produces the
same tags pointing at the same digest, because publishing is digest-first:
build to a run-unique candidate tag, attest, then move release tags onto the
attested digest. A re-run that produces an identical image re-points the same
tags; a failed attestation never leaves a published `latest` at all.

Timestamps in image labels and layer metadata mean a rebuild from the same
commit is not guaranteed to yield an identical digest. SLSA does not require
that at Build L3.

Binaries are closer, because goreleaser's `mod_timestamp: '{{ .CommitTimestamp }}'`
and `-trimpath` remove the two usual sources of drift, but this is the caller's
configuration rather than something `release-go.yaml` enforces, and the archive
still records a build time. Treat bit-for-bit reproducibility as a property you
verify, not one the level gives you.

## References

- [SLSA v1.0 build levels](https://slsa.dev/spec/v1.0/levels)
- [GitHub: artifact attestations and reusable workflows for SLSA v1 Build Level 3](https://docs.github.com/actions/security-guides/using-artifact-attestations-and-reusable-workflows-to-achieve-slsa-v1-build-level-3)
- [Fulcio OID information](https://github.com/sigstore/fulcio/blob/main/docs/oid-info.md)
- [GitHub `job` context](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#job-context)
