# Adopting these workflows

Moving an existing repository onto `build-ko.yaml` or `build-docker.yaml`. The
whole thing is usually a net deletion.

## Before you start

Decide which workflow you need:

- **Pure Go** → `build-ko.yaml`. You can delete your Dockerfile.
- **Anything else** → `build-docker.yaml`. Keep your Dockerfile.

Check the org Actions policy in [allowlist.md](allowlist.md). If your
organization allows all actions, there is nothing to do.

## The replacement

A typical existing release workflow looks something like this, and all of it
goes away:

```yaml
# BEFORE — delete all of this
jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-qemu-action@v3
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ghcr.io/thingzio/my-app
          tags: |
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
      - uses: docker/build-push-action@v6
        with:
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
      - uses: anchore/sbom-action@v0
      - run: cosign sign --yes ...
```

```yaml
# AFTER
name: Release
on:
  push:
    tags: ['v*.*.*']

permissions:
  contents: read

jobs:
  image:
    permissions:
      contents: read
      packages: write
      id-token: write
      attestations: write
    uses: thingzio/actions/.github/workflows/build-docker.yaml@<sha>  # v1.0.0
    with:
      image: thingzio/my-app
```

Things to notice in the diff:

- **`attestations: write` is new.** Without it the provenance step fails. It is
  the permission most people miss.
- **No `docker/setup-qemu-action`.** Each architecture builds on its own native
  runner, so there is no emulation to set up. If you were building arm64 under
  QEMU, expect it to get considerably faster.
- **No `docker/metadata-action`.** Tags are derived from the event; pass `tags`
  only if you need something other than the default.
- **No login step.** GHCR uses the job's `GITHUB_TOKEN`.

## Mapping your old inputs

| You had | Now |
|---|---|
| `docker/build-push-action` `context` | `context` |
| `docker/build-push-action` `file` | `dockerfile` |
| `docker/build-push-action` `platforms` | `platforms` |
| `docker/build-push-action` `target` | `target` |
| `docker/build-push-action` `build-args` | `build_args` |
| `docker/metadata-action` `tags` | `tags`, or leave it to the default |
| `docker/metadata-action` `labels` | `labels` (source, revision and version are added for you) |
| A non-GHCR registry | `registry` plus the `registry_username` / `registry_password` secrets |

## Publishing to something other than GHCR

```yaml
    uses: thingzio/actions/.github/workflows/build-docker.yaml@<sha>  # v1.0.0
    with:
      registry: docker.io
      image: thingzio/my-app
    secrets:
      registry_username: ${{ secrets.DOCKERHUB_USERNAME }}
      registry_password: ${{ secrets.DOCKERHUB_TOKEN }}
```

Pass secrets explicitly. Do not use `secrets: inherit` — these workflows declare
exactly what they accept, and inheriting everything hands a build definition
credentials it has no use for.

## Moving a Go repository to ko

If your Dockerfile is a Go builder stage copying a binary into a distroless
base, ko replaces it entirely:

```yaml
    uses: thingzio/actions/.github/workflows/build-ko.yaml@<sha>  # v1.0.0
    with:
      image: thingzio/my-app
      main: ./cmd/my-app
```

- Go version comes from your `go.mod` unless you set `go_version`.
- The base image is `cgr.dev/chainguard/static` unless your repository has a
  `.ko.yaml`, which wins, or you set `base_image`, which wins over both.
- A non-root UID is `ko_flags: --image-user=65532`.
- Delete the Dockerfile once the selftest of your own release is green.

## Building on pull requests

Add a second job with `push: false` to get build validation without publishing:

```yaml
on:
  pull_request:
  push:
    tags: ['v*.*.*']

jobs:
  image:
    permissions:
      contents: read
      packages: write
      id-token: write
      attestations: write
    uses: thingzio/actions/.github/workflows/build-ko.yaml@<sha>  # v1.0.0
    with:
      image: thingzio/my-app
      main: ./cmd/my-app
      push: ${{ github.event_name != 'pull_request' }}
```

Pull requests from forks are forced to `push: false` regardless, because a fork
has no write credential and no OIDC token. The job summary says so rather than
failing with a 403.

## Consuming the output

Deploy the digest, not a tag. A tag is a moving pointer; the digest is the thing
that was attested.

```yaml
  deploy:
    needs: image
    runs-on: ubuntu-24.04
    steps:
      - run: echo "deploying ${IMAGE_REF}"
        env:
          IMAGE_REF: ${{ needs.image.outputs.image_ref }}
```

## Verify it worked

After the first release:

```bash
gh attestation verify oci://ghcr.io/thingzio/my-app:v1.2.3 \
  --repo thingzio/my-app \
  --signer-workflow thingzio/actions/.github/workflows/build-ko.yaml
```

Add that command to your own README so your consumers can run it. Full details,
including the SBOM and admission-policy enforcement, are in
[verification.md](verification.md).

## Common first-run failures

**`Resource not accessible by integration`** — a missing permission on the
calling job. You need all four: `contents: read`, `packages: write`,
`id-token: write`, `attestations: write`.

**`image 'ghcr.io/...' names registry 'ghcr.io' but the registry input is ...`**
— `image` takes the repository path without the host. Either drop the host or
set `registry` to match.

**`unsupported platform`** — only `linux/amd64` and `linux/arm64` are
supported. Adding one means adding a runner mapping here, deliberately.

**`ko flag '--platform=all' is not allowed`** — `ko_flags` is a closed
allowlist. Use the `platforms` input.

**`denied: installation not allowed to Create organization package`** — the
package exists and is owned by a different repository, or the repository has no
package-write access. Fix it in the package's settings, not in the workflow.
