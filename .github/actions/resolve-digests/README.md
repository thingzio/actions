# `resolve-digests`

Resolves the index digest and each per-platform child manifest digest for a
pushed tag, and fails closed if the result is not the shape the build claimed.

## Usage

```yaml
- id: digests
  uses: thingzio/actions/.github/actions/resolve-digests@<sha>  # v1.0.0
  with:
    image: ghcr.io/thingzio/my-app
    tag: candidate-123-1
    platforms: '[{"platform":"linux/amd64","arch":"amd64","runner":"ubuntu-24.04"}]'
```

Requires `crane` on `PATH` — see [`setup-build-tools`](../setup-build-tools/README.md).

## Inputs

| Input | Required | Description |
|---|---|---|
| `image` | yes | Full image name including registry, without tag or digest. |
| `tag` | yes | Tag to resolve, normally the candidate tag. |
| `platforms` | yes | JSON array of `{platform, arch, runner}`. |

## Outputs

| Output | Description |
|---|---|
| `index_digest` | Index digest, or the single manifest digest for a one-platform build. Subject for provenance. |
| `platform_digests` | JSON object mapping platform to child digest. Subjects for the SBOMs. |
| `expect_index` | `"true"` when more than one platform was built. |
| `image_ref` | `<image>@<index-digest>`. |

## Why the subjects differ

`crane digest <ref>` returns the index digest, which is the right subject for
provenance and the wrong one for an SBOM. An SBOM describes exactly one root
filesystem, and a consumer that resolved `linux/amd64` enumerates referrers on
*that* child manifest, not on the index.

`crane digest --platform` resolves the index to a child and errors when the
platform is absent, so a release that silently lost an architecture fails here
rather than shipping two SBOMs pinned to the same subject.

## Fail-closed checks

Before returning, and therefore before anything is signed:

- every digest must match `^sha256:[a-f0-9]{64}$`;
- with more than one platform, each child digest must differ from the index
  digest — equality means the reference is not an index;
- the child digests must all differ from each other — equality means an
  architecture went missing;
- with exactly one platform the build legitimately produces a plain manifest, so
  both distinctness checks are skipped and the SBOM and provenance share one
  subject. That is the only case in which they do.

Logic and tests: `scripts/validate-digests.sh`, `test/validate_digests_test.sh`.
