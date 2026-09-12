# `setup-build-tools`

Installs pinned build and supply-chain tools onto the runner, verifying each
download before it can be executed.

There is no `curl | bash` here and there must never be: a piped installer runs
before anything can be verified, which is exactly the step these workflows exist
to make auditable.

## Usage

```yaml
- id: versions
  uses: thingzio/actions/.github/actions/load-versions@<sha>  # v1.0.0

- uses: thingzio/actions/.github/actions/setup-build-tools@<sha>  # v1.0.0
  with:
    ko: ${{ steps.versions.outputs.ko }}
    crane: ${{ steps.versions.outputs.crane }}
    syft: ${{ steps.versions.outputs.syft }}
    cosign: ${{ steps.versions.outputs.cosign }}
```

Every input is optional; an empty value skips that tool.

## Inputs

| Input | Default | Description |
|---|---|---|
| `ko` | `''` | ko version to install, e.g. `v0.19.1`. |
| `crane` | `''` | crane version to install. |
| `syft` | `''` | syft version to install. |
| `cosign` | `''` | cosign version to install. |

## Notes

- ko, crane and syft are downloaded by `scripts/install-tool.sh`, which verifies
  the SHA-256 against the checksum manifest each project publishes and **deletes
  the file on mismatch** so a later step cannot run it anyway.
- cosign comes from `sigstore/cosign-installer`, which verifies the project's
  own keyless signing chain — a stronger guarantee than a checksum file fetched
  from the same host as the binary.
- Tools land in `$RUNNER_TEMP/thingz-bin`, added to `PATH`. Nothing needs sudo,
  and nothing shadows a system binary for another job.
