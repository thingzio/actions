# `lint-go.yaml`

Runs **gofmt**, **go vet** and **golangci-lint** over a Go repository.

## What this does and does not cover

This is the half of a typical thingzio test workflow that is genuinely identical
everywhere. The other half is not: Postgres service definitions, DSN environment
variable names (`DEVPULSE_TEST_DSN` vs `DATABASE_URL`), package lists, and extra
tooling (devradar installs syft, grype and trivy so its live scanner tests
actually run) differ per repository in ways that would need more inputs than the
duplication is worth.

So the integration and end-to-end jobs stay in the calling repository, and only
the lint job moves here. Extracting the whole thing would trade duplicated YAML
for a longer input list, which is not a trade worth making.

## Usage

```yaml
jobs:
  lint:
    permissions:
      contents: read
    uses: thingzio/actions/.github/workflows/lint-go.yaml@<commit-sha>  # v1.3.0
```

## Inputs

| Input | Default | Description |
|---|---|---|
| `go_version` | `''` | Explicit Go version. Empty reads `go_version_file`. |
| `go_version_file` | `go.mod` | File the Go version is read from, relative to `working_directory`. |
| `working_directory` | `.` | Directory containing the Go module. |
| `golangci_version` | `''` | Override the pinned golangci-lint version. |
| `gofmt` | `true` | Fail when tracked Go files are not gofmt-clean. |
| `vet` | `true` | Run `go vet ./...`. |
| `golangci` | `true` | Run golangci-lint. |
| `timeout_minutes` | `10` | Job timeout. |

The golangci-lint version comes from
[`.versions.yaml`](../../.versions.yaml) in this repository, so every thingzio
repository lints with the same version and a bump is one PR. Override it per
repository only to stage an upgrade.

## The gofmt check

```bash
git ls-files -z -- '*.go' ':(exclude)vendor/**' | xargs -0 gofmt -l
```

`git ls-files` rather than `find`: it lists **tracked** files only, so a stray
`.go` file in a build directory cannot fail the job, and the vendor exclusion is
expressed once rather than as a path filter that has to be kept in sync.

Vendored code is excluded deliberately — it is not yours to format, and
`gofmt -l` over a vendor tree reports other people's choices as your errors.

## Turning parts off

Each check is a boolean, so a repository mid-migration can land the workflow and
enable the rest afterwards:

```yaml
    with:
      gofmt: false   # not clean yet; tracked separately
```

Prefer fixing the repository to leaving a check off. A permanently disabled
check is indistinguishable from one that does not exist.

## Notes and gotchas

- **No `args` input.** golangci-lint is configured by the repository's own
  `.golangci.yaml`, which is where linter selection belongs. An args input would
  put caller-supplied text on a command line for no benefit.
- **Renaming this file is a breaking change** for anyone pinning it.
- **The triggers belong to the caller.** This workflow has none of its own.
