# thingzio/actions

Shared CI/CD workflows and actions for the `thingzio` organization.

One place to fix a pipeline problem, one place to review a supply-chain
decision, and one identity for every repository to verify against.

- **Reusable workflows** are called at the job level and do a whole job end to
  end. These are the product.
- **Composite actions** are called at the step level, for building something
  the workflows do not cover.

Pin to a commit SHA, or track the floating `@v1` tag. See the
[latest release](https://github.com/thingzio/actions/releases/latest) for the
current version.

One exception, and it is not a style preference: **pin the release and build
workflows by SHA.** Their SLSA Build Level 3 claim rests on the build
definition being immutable, and a floating tag is a definition someone can
move. `@v1` is fine for a linter; it quietly forfeits the level for a
builder.

<!-- Deliberately not naming the version here. It was hand-maintained and went
     stale across four releases without anyone noticing, because nothing checks
     it. A link that cannot be wrong beats a number that has been. -->

---

## Reusable workflows

| Workflow | What it does | Docs |
|---|---|---|
| [`build-ko.yaml`](.github/workflows/build-ko.yaml) | Builds a **Go** repository into a multi-platform, signed, SBOM-attested container image with ko. No Dockerfile; arm64 is cross-compiled rather than emulated. | [docs](.github/workflows/build-ko.md) |
| [`release-go.yaml`](.github/workflows/release-go.yaml) | Releases a **Go** repository's binaries with goreleaser: SBOMs, a signed checksum file and SLSA Build Level 3 provenance. Signing is isolated from the caller's goreleaser hooks, which is what keeps the level. | [docs](.github/workflows/release-go.md) |
| [`build-docker.yaml`](.github/workflows/build-docker.yaml) | Builds a **Dockerfile** into a multi-platform, signed, SBOM-attested container image on native per-architecture runners. | [docs](.github/workflows/build-docker.md) |
| [`codeql-go.yaml`](.github/workflows/codeql-go.yaml) | Runs **CodeQL** over a Go repository and uploads the results to the caller's security tab. Builds explicitly, detects vendoring, and skips private repositories so it cannot start GHAS billing by surprise. | [docs](.github/workflows/codeql-go.md) |
| [`terraform-scan.yaml`](.github/workflows/terraform-scan.yaml) | Scans **Terraform** for misconfigurations with Trivy, failing on a severity threshold. Replaces tfsec, which is end of life and whose ruleset is frozen. | [docs](.github/workflows/terraform-scan.md) |
| [`lint-go.yaml`](.github/workflows/lint-go.yaml) | Runs **gofmt**, **go vet** and **golangci-lint** over a Go repository, at the org-pinned linter version. | [docs](.github/workflows/lint-go.md) |
| [`deploy-cloud-run.yaml`](.github/workflows/deploy-cloud-run.yaml) | Deploys digest-pinned images to Cloud Run services and jobs, pulling through an Artifact Registry remote repository, with optional scheduler pause/resume. | [docs](.github/workflows/deploy-cloud-run.md) |

Use `build-ko` whenever the answer is "a Go binary in a minimal base image";
use `build-docker` when the image needs system packages, a non-Go runtime, or
multiple build stages.

Both build workflows reach **SLSA v1.0 Build Level 3** — see
[SLSA](docs/slsa.md). `codeql-go`, `terraform-scan`, `lint-go` and
`deploy-cloud-run` sign nothing and publish no artifact, so
the level does not apply to it; the no-caller-supplied-code rule below still
does.

## Composite actions

> **Composite actions are SLSA Build Level 2, not 3.** They run inside a job
> you control, so the isolation the Level 3 claim rests on does not apply. Use
> a reusable workflow when the level matters.

| Action | What it does | Docs |
|---|---|---|
| [`load-versions`](.github/actions/load-versions) | Reads pinned tool versions from `.versions.yaml` | [docs](.github/actions/load-versions/README.md) |
| [`setup-go`](.github/actions/setup-go) | Configures Go from the repository's `go.mod`, caching modules only when a lock file exists | [docs](.github/actions/setup-go/README.md) |
| [`setup-build-tools`](.github/actions/setup-build-tools) | Installs ko, crane, syft and cosign, checksum-verified | [docs](.github/actions/setup-build-tools/README.md) |
| [`registry-login`](.github/actions/registry-login) | Authenticates to GHCR or any OCI registry | [docs](.github/actions/registry-login/README.md) |
| [`image-tags`](.github/actions/image-tags) | Derives release tags and the candidate tag from the event | [docs](.github/actions/image-tags/README.md) |
| [`resolve-digests`](.github/actions/resolve-digests) | Resolves index and per-platform digests, fails closed | [docs](.github/actions/resolve-digests/README.md) |
| [`sbom-attest`](.github/actions/sbom-attest) | Generates CycloneDX SBOMs and attests them with cosign | [docs](.github/actions/sbom-attest/README.md) |
| [`promote-tags`](.github/actions/promote-tags) | Moves release tags onto an attested digest | [docs](.github/actions/promote-tags/README.md) |
| [`verify-image`](.github/actions/verify-image) | Verifies provenance and SBOM attestations | [docs](.github/actions/verify-image/README.md) |

---

## Using these

Call a reusable workflow at the job level and grant it the permissions it
needs. Each workflow's document lists its inputs, outputs and required
permissions; start with [adoption](docs/migration.md) if you are converting an
existing pipeline.

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

### Pinning

Pin to a **commit SHA** with a trailing version comment. That is what this
repository does with every action it uses, what OpenSSF Scorecard's
pinned-dependencies check expects, and what Renovate and Dependabot understand.

The floating `@v1` tag is supported for teams that prefer the lower-effort
option. It moves on every compatible release, so you inherit changes without
review — a deliberate trade-off, not an oversight.

Because the Sigstore certificate identity contains the workflow filename,
**renaming a workflow file is a breaking change** even when its inputs are
unchanged.

## Conventions everything here follows

Worth reading once; it is also the bar a new workflow has to meet.

- **No caller-supplied code.** No input becomes shell, and `runs-on` comes from
  a closed allowlist. This is what the Build Level 3 claim rests on.
- **Nothing unpinned.** Every `uses:` is a commit SHA; every downloaded binary
  is checksum-verified and deleted on mismatch. No `curl | bash`.
- **Read-only by default.** `permissions: contents: read` at the top of every
  file, elevated per job only where needed.
- **Fork-safe.** `pull_request` only, never `pull_request_target`. Fork builds
  degrade to no push, no signature, and say so in the job summary.
- **Fail closed.** Inputs are validated at the boundary, and anything that
  cannot be verified stops the run rather than being warned about.
- **Publish last.** Anything that makes an artifact reachable by name happens
  only after its evidence exists, so a failed run leaves nothing behind.
- **Versions live in one file.** [`.versions.yaml`](.versions.yaml) is the
  single source of truth; nothing anywhere hardcodes a version.
- **Proven, not asserted.** [`selftest.yaml`](.github/workflows/selftest.yaml)
  exercises every workflow against real fixtures on every pull request and
  verifies the result, including the commands published for consumers. The one
  exception is `deploy-cloud-run`, which would need a disposable GCP project;
  its decision logic is unit tested with gcloud stubbed, and Cloud Run's own
  revision model means a service that fails to start never takes traffic.

## Local development

```bash
make verify   # everything CI runs: shell tests, actionlint, yamllint, shellcheck
make test     # the shell test suite
make lint     # linters only
make versions # print every pinned version
```

Tools install into `.bin/` at the pinned versions, so a laptop and a runner run
the same binaries.

## Repository layout

```
.versions.yaml            single source of truth for every tool version
.github/workflows/        reusable workflows, each with a sibling .md
                          plus this repo's own CI, selftest, release
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
| [Verification](docs/verification.md) | How to check what these workflows publish |
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
