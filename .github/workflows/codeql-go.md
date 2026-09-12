# `codeql-go.yaml`

Runs CodeQL static analysis over a Go repository and uploads the results to the
calling repository's **Security → Code scanning** tab.

It builds the module explicitly rather than using CodeQL's autobuild, because
autobuild does not reliably pick up `-mod=vendor` and most thingzio Go
repositories vendor. An analysis that silently compiles nothing still reports
success, which is the failure worth engineering against here.

> **This workflow signs nothing and publishes no artifact.** The SLSA Build
> Level 3 reasoning that shapes `build-ko.yaml` and `build-docker.yaml` does not
> apply. The no-caller-supplied-code rule still does: there is no
> `build_command` input, and `runs-on` is fixed.

## Usage

```yaml
name: codeql

on:
  schedule:
    - cron: '0 5 * * 1'
  workflow_dispatch: {}

permissions:
  contents: read

jobs:
  analyze:
    permissions:
      actions: read
      contents: read
      security-events: write
    uses: thingzio/actions/.github/workflows/codeql-go.yaml@<commit-sha>  # v1.1.0
```

That is the whole caller. A repository that vendors, one that does not, and one
that keeps its module in a subdirectory all use the same five lines.

## Inputs

| Input | Default | Description |
|---|---|---|
| `go_version` | `''` | Explicit Go version. Empty reads `go_version_file`. |
| `go_version_file` | `go.mod` | File the Go version is read from, relative to `working_directory`. Ignored when `go_version` is set. |
| `working_directory` | `.` | Directory containing the Go module. |
| `category` | `''` | Code-scanning category. Required when one repository calls this workflow more than once. |
| `run_on_private` | `false` | Analyze even when the repository is private. |
| `timeout_minutes` | `30` | Job timeout. |

### Permissions

| Permission | Why |
|---|---|
| `security-events: write` | Upload the SARIF results |
| `actions: read` | CodeQL reads workflow run metadata |
| `contents: read` | Check out the source |

## Outputs

None. The result is the code-scanning alerts in the calling repository.

## Billing, and why private repositories are skipped by default

CodeQL is free on public repositories and billed as **GitHub Advanced
Security** on private ones. The analysis job is therefore gated:

```yaml
if: inputs.run_on_private || github.event.repository.visibility == 'public'
```

A private repository that adopts this workflow gets a green no-op, and starts
being analyzed by itself on the day it is made public. Nothing has to be
remembered at flip time, and nothing starts billing by surprise. Set
`run_on_private: true` if the organization has GHAS and wants the analysis now.

## Vendoring

Detected, not configured. When `vendor/modules.txt` is present the build step
exports `GOFLAGS=-mod=vendor` and says so in the log.

Go already enables vendor mode by itself when that file exists, so this mostly
makes the intent visible — but it also means there is no input a caller can set
wrongly, and no repository that has to remember to set it.

## Examples

**A module in a subdirectory**

```yaml
    uses: thingzio/actions/.github/workflows/codeql-go.yaml@<commit-sha>  # v1.1.0
    with:
      working_directory: api
```

**A repository whose toolchain lives in `.go-version` rather than `go.mod`**

```yaml
    uses: thingzio/actions/.github/workflows/codeql-go.yaml@<commit-sha>  # v1.1.0
    with:
      go_version_file: .go-version
```

**Run on a private repository (requires GHAS)**

```yaml
    uses: thingzio/actions/.github/workflows/codeql-go.yaml@<commit-sha>  # v1.1.0
    with:
      run_on_private: true
```

## How it works

1. Checks the caller's source out at the **workspace root**. CodeQL reports
   SARIF paths relative to the workspace, so a subdirectory checkout would give
   every finding a bogus prefix and break the links from the security tab to the
   source. This is why the layout differs from the build workflows, which put
   the caller's source in `src/`.
2. Checks this repository out into `.builder/`, at `job.workflow_sha`, to reach
   its own scripts. A relative path inside a reusable workflow resolves against
   the caller, so there is no other way. The leading dot also keeps it out of
   `go build ./...`, which ignores dot directories.
3. Resolves the module directory and the module-cache key with
   `scripts/actions/go-module-cache.sh`, shared with the build workflows.
4. Sets up Go, enabling the module cache only when a `go.sum` exists — a module
   with no third-party dependencies legitimately has none, and `setup-go` fails
   outright rather than degrading when caching is on and it cannot find a lock
   file.
5. `codeql-action/init` with `languages: go`, then `go build ./...`, then
   `codeql-action/analyze`.

## Notes and gotchas

- **Renaming this file is a breaking change** for anyone pinning it, in the same
  way it is for the build workflows.
- **Calling this twice in one repository requires `category`.** CodeQL derives a
  default category from the workflow file and job name; both are identical for
  every call of a reusable workflow, so two analyses would otherwise overwrite
  each other's results. Give each call its own `category`:

  ```yaml
  jobs:
    api:
      uses: thingzio/actions/.github/workflows/codeql-go.yaml@<commit-sha>  # v1.1.0
      with:
        working_directory: api
        category: /module:api
  ```
- **`build-mode: none` is not used.** The Go extractor rejects it; the build is
  what produces the database.
- **The schedule belongs to the caller.** This workflow has no triggers of its
  own, so each repository decides how often it runs.
