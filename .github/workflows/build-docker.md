# `build-docker.yaml`

Builds a Dockerfile into a multi-platform container image on native runners,
attests a CycloneDX SBOM to each platform manifest, and attaches SLSA build
provenance to the index.

Each architecture builds on its own native runner and the results are merged
into an index. Emulating `linux/arm64` through QEMU in a single job would be
simpler YAML and far slower for anything that compiles or resolves packages.

Building a pure-Go repository? [`build-ko.yaml`](build-ko.md) is faster, needs
no Dockerfile, and produces a smaller image.

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
    uses: thingzio/actions/.github/workflows/build-docker.yaml@<sha>  # v1.0.0
    with:
      image: thingzio/my-app
```

All four permissions are required. `attestations: write` is the one most people
miss; without it the provenance step fails at the end of an otherwise
successful build.

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `image` | string | *required* | Repository path **without** the registry host, tag or digest, e.g. `thingzio/my-app`. A value carrying a host is accepted only when it matches `registry`. |
| `registry` | string | `ghcr.io` | Registry host to publish to. |
| `dockerfile` | string | `./Dockerfile` | Path relative to the repository root. |
| `context` | string | `.` | Build context relative to the repository root. |
| `target` | string | `''` | Dockerfile stage to build; empty builds the final stage. |
| `build_args` | string | `''` | One `key=value` per line. Values may contain commas. |
| `platforms` | string | `linux/amd64,linux/arm64` | `linux/amd64` and `linux/arm64` only. |
| `tags` | string | derived | Newline- or comma-separated; replaces the derived set entirely. |
| `labels` | string | `''` | Additional OCI labels, one `key=value` per line. |
| `cache` | boolean | `true` | Use the GitHub Actions cache backend, scoped per architecture. |
| `push` | boolean | `true` | Forced to `false` on fork pull requests. |
| `sbom` | boolean | `true` | Generate and attest a CycloneDX SBOM per platform. |
| `provenance` | boolean | `true` | Attach SLSA build provenance to the index. |
| `cosign_version`, `syft_version`, `crane_version` | string | from `.versions.yaml` | Per-call override for emergency pinning. |

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

## Tags published

| Trigger | Tags |
|---|---|
| tag push `v1.2.3` | `v1.2.3`, `v1.2`, `v1`, `latest` |
| tag push `v1.2.3-rc.1` | `v1.2.3-rc.1` only |
| push to default branch | `sha-<short>`, and the branch name |
| push to another branch | `sha-<short>` |
| pull request | `pr-<number>` |

A prerelease never claims `latest` or a moving major tag.

## Examples

**Multi-stage build with arguments**

```yaml
    with:
      image: thingzio/my-app
      dockerfile: build/Dockerfile
      context: .
      target: runtime
      build_args: |
        VERSION=1.2.3
        FEATURES=a,b,c
```

**Publishing to Docker Hub**

```yaml
    with:
      registry: docker.io
      image: thingzio/my-app
    secrets:
      registry_username: ${{ secrets.DOCKERHUB_USERNAME }}
      registry_password: ${{ secrets.DOCKERHUB_TOKEN }}
```

**Single platform**

```yaml
    with:
      image: thingzio/my-app
      platforms: linux/amd64
```

With one platform the build stays a plain manifest rather than being wrapped in
an index, and the SBOM and the provenance share a subject digest. That is the
only case in which they do.

**No layer cache**

```yaml
      cache: false
```

Worth doing when a build step resolves dependencies dynamically — an unpinned
`pip install` or `apt-get`, say. BuildKit cannot see inside those commands, so
neither the base image nor the copied manifest changes between releases, a
cache hit replays the old closure verbatim, and the image silently stops
picking up patched versions.

## Verifying the result

```bash
gh attestation verify oci://ghcr.io/thingzio/my-app:v1.2.3 \
  --repo thingzio/my-app \
  --signer-workflow thingzio/actions/.github/workflows/build-docker.yaml
```

See [docs/verification.md](../../docs/verification.md) for the SBOM, the cosign
equivalent, and admission-policy enforcement.

## How it works

```
prepare   validate inputs, derive tags, map platforms → native runners
   │
build     one job per platform, on its own native runner
   ├─ linux/amd64 on ubuntu-24.04      → push <candidate>-amd64
   └─ linux/arm64 on ubuntu-24.04-arm  → push <candidate>-arm64
   │
publish   imagetools create → index at <candidate>
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
- **BuildKit's own attestations are disabled.** `provenance: false` and
  `sbom: false` are passed to `docker/build-push-action` on purpose: they would
  wrap even a single-platform build in an index, changing what the digest refers
  to, and this workflow publishes its own attestations with deliberate subjects.
- **`fail-fast` is off across the platform matrix.** One architecture failing
  should not hide whether the other one works.
- **The cache is scoped per architecture**, so an amd64 build cannot pollute the
  arm64 cache.
- **Per-architecture staging tags** (`<candidate>-amd64`) and the candidate tag
  are left in the registry. GHCR cannot delete a tag without deleting the
  underlying manifest.
- **Pin your base image by digest.** A mutable base tag means the same source
  can produce different bytes, which undermines everything the attestation says.
- **This is a trusted build definition.** There is no input that runs your
  commands, and you cannot choose the runner. Your Dockerfile fully determines
  the image contents but cannot reach the job's OIDC token. See
  [docs/slsa.md](../../docs/slsa.md).
