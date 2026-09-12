# `promote-tags`

Points the release tags at an already-attested digest. This is the last step of
a build and the only one that makes an image reachable by name.

## Usage

```yaml
- uses: thingzio/actions/.github/actions/promote-tags@<sha>  # v1.0.0
  with:
    image: ghcr.io/thingzio/my-app
    digest: ${{ steps.digests.outputs.index_digest }}
    tags: ${{ steps.tags.outputs.tags }}
```

Requires `crane` on `PATH` and a registry login with push access.

## Inputs

| Input | Required | Description |
|---|---|---|
| `image` | yes | Full image name including registry, without tag or digest. |
| `digest` | yes | Attested index digest to point the tags at. |
| `tags` | yes | Newline-separated tags to publish. |

## Why this is a separate step

Digest-first publishing. The build pushes to a run-unique candidate tag, the
attestations are signed against the resulting digests, and only then do the
release tags move. A failed signing step therefore cannot leave a published
`latest`, and a re-run re-points the same tags at the same digest.

`crane tag` re-points a tag at an existing manifest without moving any layers,
so promotion is a registry-side metadata change rather than a second upload that
could produce a different digest.

## Notes

Every tag is re-validated against the OCI tag grammar here rather than trusted.
This action is public and may be used outside the reusable workflows, where
nothing upstream has checked it.
