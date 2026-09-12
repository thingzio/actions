# thingzio/actions

Shared CI/CD workflows for the `thingzio` organization.

One place to fix a build problem, one place to review a supply-chain decision,
and one identity for every repository to verify against. Publishing a signed,
SBOM-attested container image should be ten lines in a consumer repository, not
a hundred lines of copied YAML that drifts.

```yaml
jobs:
  image:
    permissions:
      contents: read
      packages: write
      id-token: write
      attestations: write
    uses: thingzio/actions/.github/workflows/build-ko.yaml@<commit-sha>  # v1.0.0
    with:
      image: thingzio/my-app
      main: ./cmd/my-app
```

That publishes `ghcr.io/thingzio/my-app` tagged `v1.2.3`, `v1.2`, `v1` and
`latest`, with a CycloneDX SBOM attested to each platform manifest and SLSA
build provenance on the index — verifiable at **SLSA v1.0 Build Level 3**.

---

## Catalog

### Reusable workflows

Called with `uses:` at the job level. **These are the product.** Each one is a
trusted build definition; the Build Level 3 claim depends on callers being
unable to alter what runs inside them.

| Workflow | Purpose | Docs |
|---|---|---|
| `build-ko.yaml` | Build a Go repository into a multi-platform image with ko, SBOM-attested and signed. No Dockerfile. | [docs](.github/workflows/build-ko.md) |
| `build-docker.yaml` | Build a Dockerfile into a multi-platform image on native runners, SBOM-attested and signed. | [docs](.github/workflows/build-docker.md) |

**Which one?** Reach for `build-ko` whenever the answer is "a Go binary in a
minimal base image" — it is faster, needs no Dockerfile, produces a smaller
image, and cross-compiles arm64 instead of emulating it. Reach for
`build-docker` when the image needs system packages, a non-Go runtime, or
multiple build stages.

### Composite actions

Called with `uses:` at the step level, for building something these workflows
do not cover.

> **Composite actions are SLSA Build Level 2, not 3.** They run inside a job
> you control, so the isolation the Level 3 claim rests on does not apply. Use
> the reusable workflows above when the level matters. See [SLSA](docs/slsa.md).

| Action | Purpose | Docs |
|---|---|---|
| `load-versions` | Read pinned tool versions from `.versions.yaml` | [docs](.github/actions/load-versions/README.md) |
| `setup-build-tools` | Install ko, crane, syft, cosign with checksum verification | [docs](.github/actions/setup-build-tools/README.md) |
| `registry-login` | Authenticate to GHCR or any OCI registry | [docs](.github/actions/registry-login/README.md) |
| `image-tags` | Derive release tags and the candidate tag from the event | [docs](.github/actions/image-tags/README.md) |
| `resolve-digests` | Resolve index and per-platform digests, fail closed | [docs](.github/actions/resolve-digests/README.md) |
| `sbom-attest` | Generate CycloneDX SBOMs and attest them with cosign | [docs](.github/actions/sbom-attest/README.md) |
| `promote-tags` | Move release tags onto an attested digest | [docs](.github/actions/promote-tags/README.md) |
| `verify-image` | Verify provenance and SBOM attestations | [docs](.github/actions/verify-image/README.md) |

### This repository's own CI

Not for external use, but worth knowing they exist: `ci.yaml` (lint and unit
tests), `selftest.yaml` (builds the `testdata/` fixtures for real and verifies
the attestations), `codeql.yaml`, `scorecard.yaml`, `release.yaml`.

---

## Verifying what these workflows publish

```bash
gh attestation verify oci://ghcr.io/thingzio/my-app:v1.2.3 \
  --repo thingzio/my-app \
  --signer-workflow thingzio/actions/.github/workflows/build-ko.yaml
```

`--repo` says where the attestation is stored (your repository);
`--signer-workflow` asserts who signed it (the shared build definition).
Separating the two is what stops anyone from minting provenance claiming these
workflows produced their image.

Full detail — SBOM verification, reading the provenance, admission policies:
[docs/verification.md](docs/verification.md).

## Pinning

Pin to a **commit SHA** with a version comment:

```yaml
uses: thingzio/actions/.github/workflows/build-ko.yaml@1a2b3c4…  # v1.0.0
```

That is what this repository does with every action it uses, and what OpenSSF
Scorecard's pinned-dependencies check expects. Renovate and Dependabot both
understand the trailing comment.

The floating `@v1` tag is supported for teams that prefer the lower-effort
option. It moves on every compatible release, so you inherit changes without
review — a deliberate trade-off, not an oversight.

Because the Sigstore certificate identity contains the workflow filename,
**renaming a workflow file is a breaking change** even when its inputs are
unchanged.

## Conventions every workflow here follows

Useful to know before reading any individual document, and the rules any new
workflow must meet:

- **Digest-first publishing.** Build to a run-unique candidate tag, attest, then
  move release tags onto the attested digest. A failed signing step cannot leave
  a published `latest`, and a re-run re-points the same tags at the same digest.
- **SBOMs on platform manifests, provenance on the index.** An SBOM describes
  one root filesystem; provenance describes the build that produced the whole
  image.
- **Fail closed.** Digests are validated for shape and distinctness, and an
  SBOM's format is asserted, before anything is signed.
- **No caller-supplied code.** No input becomes shell, and `runs-on` comes from
  a closed allowlist. This is what the Build Level 3 claim rests on.
- **Nothing unpinned.** Every `uses:` is a commit SHA; every downloaded binary
  is checksum-verified and deleted on mismatch. No `curl | bash`.
- **Fork-safe.** `pull_request` only, never `pull_request_target`. Fork builds
  degrade to no push, no signature, and say so.
- **Read-only by default.** `permissions: contents: read` at the top of every
  file, elevated per job only where needed.

## Local development

```bash
make verify   # everything CI runs: shell tests, actionlint, yamllint, shellcheck
make test     # the shell test suite
make lint     # linters only
make versions # print every pinned version
```

Tools install into `.bin/` at the versions pinned in
[`.versions.yaml`](.versions.yaml), so a laptop and a runner run the same
binaries. Nothing anywhere hardcodes a version.

## Repository layout

```
.versions.yaml            single source of truth for every tool version
.github/workflows/        reusable workflows (the product) + this repo's own CI
                          each reusable workflow has a sibling .md
.github/actions/          composite actions, each with a README
scripts/                  validation and tag logic, unit tested
scripts/actions/          the shell behind each composite action
test/                     zero-dependency shell test harness
testdata/                 fixtures the selftest builds for real
docs/                     cross-cutting: verification, SLSA, adoption, org policy
```

## Documentation

| | |
|---|---|
| [Verification](docs/verification.md) | Every way to check an image, plus admission policies |
| [SLSA](docs/slsa.md) | What level, why it holds, and what would break it |
| [Adoption](docs/migration.md) | Moving an existing repository onto these workflows |
| [Org allowlist](docs/allowlist.md) | Actions policy a consuming org needs |
| [Contributing](CONTRIBUTING.md) | Setup, the trust-boundary rules, how tests work |
| [Releasing](RELEASING.md) | For maintainers |
| [Security policy](SECURITY.md) | Reporting, scope, and posture |
| [Maintainers](MAINTAINERS.md) | Who to ask |
| [Rulesets](.github/rulesets/README.md) | Branch and tag protection as code |

## License

[Apache 2.0](LICENSE). See [NOTICE](NOTICE).
