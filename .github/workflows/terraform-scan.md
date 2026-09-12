# `terraform-scan.yaml`

Scans Terraform for misconfigurations with [Trivy](https://trivy.dev) and fails
the job when a finding meets the severity threshold.

## Why Trivy and not tfsec

tfsec is end of life. Its final release was **v1.28.14 in May 2025**, and the
project's own repository description now reads *"Tfsec is now part of Trivy"*.
A repository still running it is scanning against a frozen 2025 ruleset and
will never learn anything new — which is a worse failure than a scanner that
occasionally disagrees with you, because it looks like success.

`trivy config` covers the same ground and is maintained.

## Usage

```yaml
name: terraform

on:
  push:
    branches: [main]
    paths: ['infra/**']
  pull_request:
    branches: [main]
    paths: ['infra/**']

permissions:
  contents: read

jobs:
  scan:
    permissions:
      contents: read
    uses: thingzio/actions/.github/workflows/terraform-scan.yaml@<commit-sha>  # v1.2.0
    with:
      working_directory: infra/run
```

## Inputs

| Input | Default | Description |
|---|---|---|
| `working_directory` | `.` | Directory to scan, relative to the repository root. |
| `severity` | `HIGH,CRITICAL` | Comma-separated severities that fail the job. One or more of `UNKNOWN`, `LOW`, `MEDIUM`, `HIGH`, `CRITICAL`. |
| `exit_code` | `1` | Exit code when a finding meets the threshold. `0` reports without failing. |
| `trivy_version` | `''` | Override the pinned Trivy version. |

## Outputs

| Output | Description |
|---|---|
| `findings` | Number of findings at or above the severity threshold |

## Adopting this on a repository with a backlog

Set `exit_code: 0`. The scan runs, the job summary reports the count, and
nothing goes red:

```yaml
    with:
      working_directory: infra
      exit_code: 0
```

Triage, then remove the input. Leaving it at `0` permanently is the same as not
running the scan, so it is worth treating as a dated exception rather than a
setting.

## Severity is validated, not passed through

`severity` reaches a command line, so it is checked against a closed allowlist
and normalized to upper case. This is not ceremony: `HIGH,CRITCAL` passed
through unchecked scans for `HIGH` alone and reports success. A typo that
silently narrows a security gate is exactly the kind of failure that goes
unnoticed for a year, so it fails the job instead.

`HIGH, CRITICAL` with a space works. `SEVERE` does not.

## How it works

1. Checks the caller's source into `src/` and this repository into `.builder/`.
2. Installs the pinned Trivy with `scripts/install-tool.sh`, which verifies the
   SHA-256 against the project's published checksum manifest. No `curl | bash`.
3. Runs `trivy config` twice over the same target: once as JSON with
   `--exit-code 0` so the finding count is a number rather than something
   scraped out of a table, then once as a table for a human reading the log,
   carrying the real exit code.
4. Writes the count to the job summary and to the `findings` output.

## Notes and gotchas

- **`working_directory` must exist.** A typo fails the job before Trivy runs,
  rather than scanning nothing and passing.
- **Findings are not uploaded to code scanning.** They appear in the job log and
  the summary. If you want them in the security tab, that is a SARIF upload and
  a `security-events: write` permission — open an issue and it can be added as
  an input.
- **Renaming this file is a breaking change** for anyone pinning it.
- **The triggers belong to the caller.** This workflow has none of its own, so
  each repository decides when it runs and which paths matter.
