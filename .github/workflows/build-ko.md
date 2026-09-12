# `build-ko.yaml`

Builds a Go repository into a multi-platform container image with
[ko](https://ko.build), attests a CycloneDX SBOM to each platform manifest, and
attaches SLSA build provenance to the index.

No Dockerfile. ko cross-compiles Go natively, so both architectures come out of
a single job with no QEMU, no build matrix and no manifest merge.

Needs a Dockerfile, system packages, or a non-Go runtime? Use
[`build-docker.yaml`](build-docker.md) instead.

## Usage

```yaml
name: Release
on:
  push:
    tags: ['v*.*.*']

permissions:
  contents: read

jobs:
  image:
    permissions:
      contents: read        # checkout
      packages: write       # push to GHCR
      id-token: write       # keyless Cosign + provenance
      attestations: write   # store the attestation
    uses: thingzio/actions/.github/workflows/build-ko.yaml@<sha>  # v1.0.0
    with:
      image: thingzio/my-app
      main: ./cmd/my-app
```

All four permissions are required. `attestations: write` is the one most people
miss; without it the provenance step fails at the end of an otherwise
successful build.

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `image` | string | *required* | Repository path **without** the registry host, tag or digest, e.g. `thingzio/my-app`. A value carrying a host is accepted only when it matches `registry`. |
| `registry` | string | `ghcr.io` | Registry host to publish to. |
| `main` | string | `.` | Go main package path, e.g. `./cmd/my-app`. |
| `working_directory` | string | `.` | Directory containing the Go module, when it is not the repository root. |
| `go_version` | string | `''` | Empty reads the version from your `go.mod`. |
| `base_image` | string | `''` | Empty uses your `.ko.yaml` if present, otherwise the org default from `.versions.yaml`. |
| `platforms` | string | `linux/amd64,linux/arm64` | `linux/amd64` and `linux/arm64` only. |
| `tags` | string | derived | Newline- or comma-separated; replaces the derived set entirely. |
| `labels` | string | `''` | Additional OCI labels, one `key=value` per line. |
| `ko_flags` | string | `''` | Allowlisted only: `--image-user=<uid>`, `--image-annotation=<k>=<v>`, `--disable-optimizations`, `--debug`. |
| `push` | boolean | `true` | Forced to `false` on fork pull requests. |
| `sbom` | boolean | `true` | Generate and attest a CycloneDX SBOM per platform. |
| `provenance` | boolean | `true` | Attach SLSA build provenance to the index. |
| `ko_version`, `cosign_version`, `syft_version`, `crane_version` | string | from `.versions.yaml` | Per-call override for emergency pinning. |

### Secrets

| Secret | Required | Description |
|---|---|---|
| `registry_username` | no | Omit for GHCR; defaults to `github.actor`. |
| `registry_password` | no | Omit for GHCR; defaults to the job's `GITHUB_TOKEN`. |

Pass secrets explicitly. Do not use `secrets: inherit`.

## Outputs

| Output | Description |
|---|---|
| `digest` | Index digest, `sha256:…`. |
| `image_ref` | `<registry>/<image>@<digest>` — deploy this, not a tag. |
| `tags` | Newline-separated tags that were published. |
| `platform_digests` | JSON object: `{"linux/amd64":"sha256:…", …}`. |

```yaml
  deploy:
    needs: image
    runs-on: ubuntu-24.04
    steps:
      - run: echo "deploying ${IMAGE_REF}"
        env:
          IMAGE_REF: ${{ needs.image.outputs.image_ref }}
```

## Tags published

| Trigger | Tags |
|---|---|
| tag push `v1.2.3` | `v1.2.3`, `v1.2`, `v1`, `latest` |
| tag push `v1.2.3-rc.1` | `v1.2.3-rc.1` only |
| push to default branch | `sha-<short>`, and the branch name |
| push to another branch | `sha-<short>` |
| pull request | `pr-<number>` |

A prerelease never claims `latest` or a moving major tag.

## Base image

Precedence, highest first:

1. The `base_image` input.
2. A `.ko.yaml` in your `working_directory`. A repository that has deliberately
   pinned a base is never silently overridden.
3. `images.ko_default_base` from this repository's `.versions.yaml`
   (`cgr.dev/chainguard/static`).

## Examples

**Non-root user and extra labels**

```yaml
    with:
      image: thingzio/my-app
      main: ./cmd/my-app
      ko_flags: --image-user=65532
      labels: |
        org.opencontainers.image.description=Widget service, with commas allowed
        org.opencontainers.image.licenses=Apache-2.0
```

**Module in a subdirectory, single platform**

```yaml
    with:
      image: thingzio/my-app
      working_directory: services/api
      main: ./cmd/server
      platforms: linux/amd64
```

With one platform the build produces a plain manifest rather than an index, and
the SBOM and the provenance share a subject digest. That is the only case in
which they do.

**Validate on pull requests without publishing**

```yaml
      push: ${{ github.event_name != 'pull_request' }}
```

## Verifying the result

```bash
gh attestation verify oci://ghcr.io/thingzio/my-app:v1.2.3 \
  --repo thingzio/my-app \
  --signer-workflow thingzio/actions/.github/workflows/build-ko.yaml
```

See [docs/verification.md](../../docs/verification.md) for the SBOM, the cosign
equivalent, and admission-policy enforcement.

## How it works

```
prepare   validate inputs, derive tags, resolve pinned versions
   │
publish   checkout source to src/ and this repo to .builder/
          setup Go (from your go.mod) and the pinned tools
          ko build --bare --platform=… --tags=<candidate>   ← run-unique tag
          crane digest → index + per-platform, validated fail-closed
          syft → CycloneDX per platform → cosign attest to each child manifest
          actions/attest-build-provenance → the index digest
          crane tag → move the release tags onto the attested digest
```

The release tags move **last**. A failed attestation cannot leave a published
`latest`, and a re-run re-points the same tags at the same digest.

## Notes and gotchas

- **`image` excludes the registry host.** `thingzio/my-app`, not
  `ghcr.io/thingzio/my-app`. The full form is accepted when the host matches
  `registry`, and rejected otherwise rather than silently publishing elsewhere.
- **Labels may contain commas.** ko's `--image-label` is a CSV-parsed slice; the
  workflow quotes each label so a description with a comma survives intact. An
  `--image-annotation` passed through `ko_flags` does **not** get this
  treatment — avoid commas there.
- **No module cache without a `go.sum`.** A module with no third-party
  dependencies has none, and `setup-go` fails rather than degrading, so the
  workflow detects this and disables the cache.
- **Candidate tags are left in the registry.** GHCR cannot delete a tag without
  deleting the underlying manifest. They are cheap and useful forensically.
- **This is a trusted build definition.** There is no input that runs your
  commands, and you cannot choose the runner. See [docs/slsa.md](../../docs/slsa.md).
