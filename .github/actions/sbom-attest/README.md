# `sbom-attest`

Generates a CycloneDX SBOM per platform, attests each one to its own child
manifest with keyless Cosign, and attaches SLSA build provenance to the index.

## Usage

```yaml
- uses: thingzio/actions/.github/actions/sbom-attest@<sha>  # v1.0.0
  with:
    image: ghcr.io/thingzio/my-app
    index_digest: ${{ steps.digests.outputs.index_digest }}
    platform_digests: ${{ steps.digests.outputs.platform_digests }}
```

Requires `syft` and `cosign` on `PATH`, a registry login, and
`id-token: write` plus `attestations: write` on the job.

> **From your own workflow this is SLSA Build Level 2, not 3.** The level
> depends on the build and the attestation running in a reusable workflow a
> caller cannot inject steps into. See [docs/slsa.md](../../../docs/slsa.md).

## Inputs

| Input | Default | Description |
|---|---|---|
| `image` | *required* | Full image name including registry, without tag or digest. |
| `index_digest` | *required* | Index digest; subject for provenance. |
| `platform_digests` | *required* | JSON object mapping platform to child digest. |
| `sbom` | `true` | Generate and attest CycloneDX SBOMs. |
| `provenance` | `true` | Attach build provenance to the index. |

## Subject policy

| Predicate | Subject | Why |
|---|---|---|
| CycloneDX SBOM | each **platform** child manifest | An SBOM describes exactly one root filesystem. A referrer descriptor carries only digest, mediaType, size, artifactType and annotations — no name — so two CycloneDX documents on one index digest are indistinguishable in a referrers listing without pulling every payload. A consumer that resolved `linux/amd64` looks on that child manifest. |
| SLSA provenance | the **index** digest | It describes the build that produced the whole release image, not one architecture of it. |

## Notes

- `--new-bundle-format=true` is passed explicitly rather than inherited from
  whatever the installed cosign defaults to. It is what publishes through the
  OCI referrers API instead of a legacy `.att` tag, and that must be this
  repository's decision, not one that can move between cosign releases.
- Each SBOM's `bomFormat` and `specVersion` are asserted, and an empty component
  list is rejected, **before** `cosign attest` runs. `cosign attest --type
  cyclonedx` stamps the CycloneDX predicate type on whatever bytes it is handed,
  so a silently-wrong document would publish as correct.
- `ghcr.io` does not implement the OCI 1.1 referrers endpoint, so attestations
  land through the specification's referrers tag fallback (`sha256-<hex>`).
  Transparent to cosign, oras and gh; invisible to a raw `curl`.
- SBOMs are also uploaded as a workflow artifact, retained 30 days.
