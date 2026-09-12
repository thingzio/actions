# `registry-login`

Authenticates to an OCI registry. Defaults to GitHub Container Registry using
the job's `GITHUB_TOKEN`, so the common case needs no secret at all.

## Usage

```yaml
# GHCR — nothing to configure
- uses: thingzio/actions/.github/actions/registry-login@<sha>  # v1.0.0

# Any other registry
- uses: thingzio/actions/.github/actions/registry-login@<sha>  # v1.0.0
  with:
    registry: docker.io
    username: ${{ secrets.DOCKERHUB_USERNAME }}
    password: ${{ secrets.DOCKERHUB_TOKEN }}
```

Requires `packages: write` on the job when pushing to GHCR.

## Inputs

| Input | Default | Description |
|---|---|---|
| `registry` | `ghcr.io` | Registry host, optionally with a port. |
| `username` | `github.actor` | Registry username. |
| `password` | `github.token` | Registry password or token. The default is valid for ghcr.io only. |

## Notes

The registry host is validated before the login action sees it, so a malformed
value fails with an actionable message rather than a docker CLI error, and a
newline can never reach the credential helper.
