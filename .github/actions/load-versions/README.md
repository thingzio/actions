# `load-versions`

Reads the pinned tool versions from [`.versions.yaml`](../../../.versions.yaml)
and exposes them as step outputs.

Resolving versions through this action rather than inline is what makes
`.versions.yaml` the single source of truth: `make lint` on a laptop and the
`ci` workflow install the same binaries, and a bump is one reviewed PR that the
selftest proves before it merges.

## Usage

```yaml
- id: versions
  uses: thingzio/actions/.github/actions/load-versions@<sha>  # v1.0.0

- uses: sigstore/cosign-installer@<sha>  # v4.1.2
  with:
    cosign-release: ${{ steps.versions.outputs.cosign }}
```

## Outputs

| Output | Example |
|---|---|
| `ko` | `v0.19.1` |
| `crane` | `v0.22.1` |
| `syft` | `v1.51.1` |
| `goreleaser` | `v2.18.1` |
| `cosign` | `v3.1.3` — pinned `>= v3.1.0` so DSSE attestations reach Rekor v2 as `hashedrekord`/PAE rather than the legacy `dsse` entry type, which `sigstore-go` cannot verify |
| `trivy` | `v0.74.0` |
| `golangci_lint` | `v2.13.1` |
| `actionlint` | `v1.7.12` |
| `yamllint` | `1.38.0` |
| `shellcheck` | `v0.11.0` |
| `zizmor` | `1.30.1` — unprefixed, because `pip` and the `zizmor` container tag both want it that way |
| `ko_default_base` | `cgr.dev/chainguard/static:latest` |

## Notes

Takes no inputs. Reads the `.versions.yaml` that sits beside the action, so the
values always match the commit the action was resolved at.
