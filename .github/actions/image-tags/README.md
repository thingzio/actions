# `image-tags`

Derives the image tags for a build from the event context, plus the run-unique
candidate tag a build publishes to before it is promoted.

Builds publish to the candidate tag first and move the release tags onto the
resulting digest only after attestation succeeds, so a failed signing step never
leaves a published `latest`. The candidate tag is what makes that two-phase
publish possible.

## Usage

```yaml
- id: tags
  uses: thingzio/actions/.github/actions/image-tags@<sha>  # v1.0.0

- run: echo "publishing ${{ steps.tags.outputs.primary_tag }}"
```

## Inputs

| Input | Default | Description |
|---|---|---|
| `tags` | `''` | Newline- or comma-separated tags that replace the derived set entirely. |

## Outputs

| Output | Description |
|---|---|
| `tags` | Newline-separated release tags. |
| `primary_tag` | The first release tag, useful for the version label. |
| `candidate_tag` | `candidate-<run-id>-<run-attempt>`. |

## Derived tags

| Trigger | Tags |
|---|---|
| tag push `v1.2.3` | `v1.2.3`, `v1.2`, `v1`, `latest` |
| tag push `v1.2.3-rc.1` | `v1.2.3-rc.1` only |
| push to default branch | `sha-<short>`, and the branch name |
| push to another branch | `sha-<short>` |
| pull request | `pr-<number>` |

## Notes

- A prerelease never claims `latest` or a moving major tag.
- Refs are sanitized rather than rejected: a branch called `release/v2` is legal
  in git and illegal as an OCI tag, so it becomes `release-v2`.
- Overrides strip whitespace rather than splitting on it, so `good evil` cannot
  become two tags. Every tag, derived or supplied, is validated against the OCI
  tag grammar before it is emitted.
- Logic and tests live in `scripts/derive-tags.sh` and
  `test/derive_tags_test.sh`.
