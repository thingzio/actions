# Verifying a release

These workflows publish two kinds of artifact — container images and Go
binaries — and both carry signed evidence. Images are covered first; jump to
[Verifying a binary](#verifying-a-binary) for `release-go.yaml` releases.

## Images

Every image these workflows publish carries two kinds of signed evidence:

| Evidence | Subject | Predicate type |
|---|---|---|
| SLSA build provenance | the image **index** digest | `https://slsa.dev/provenance/v1` |
| CycloneDX SBOM | each **platform** manifest digest | `https://cyclonedx.org/bom` |

Both are keyless: signed with a short-lived certificate from Sigstore's Fulcio,
bound to the GitHub OIDC identity of the workflow that produced them, and logged
to Rekor. There is no key to rotate and none to steal.

## Quick check

```bash
gh attestation verify oci://ghcr.io/thingzio/my-app:v1.2.3 \
  --repo thingzio/my-app \
  --signer-workflow thingzio/actions/.github/workflows/build-ko.yaml
```

Both flags matter, and they do different jobs:

- `--repo` — where the attestation is **stored**. Always the repository whose
  workflow called the builder.
- `--signer-workflow` — who **signed** it, as
  `[host/]<owner>/<repo>/<path>`. Always the shared build definition.

Checking only `--repo` would accept an attestation a repository minted for
itself. Pinning the signer is what makes the claim mean "built by the reviewed,
shared build definition".

`--signer-repo` also exists and takes just `<owner>/<repo>`, but the two are
**mutually exclusive** — `gh` rejects the combination. `--signer-workflow`
already carries the repository and pins the exact build definition, so prefer
it.

## Verify the SBOM

An SBOM describes one root filesystem, so it is attached to a platform
manifest rather than to the index. Resolve the platform you care about first:

```bash
IMAGE=ghcr.io/thingzio/my-app
INDEX=$(crane digest "${IMAGE}:v1.2.3")
AMD64=$(crane digest --platform linux/amd64 "${IMAGE}@${INDEX}")

cosign verify-attestation \
  --type cyclonedx \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github\.com/thingzio/actions/\.github/workflows/build-ko\.yaml@' \
  --certificate-github-workflow-repository thingzio/my-app \
  "${IMAGE}@${AMD64}"
```

The identity regexp is anchored on the workflow path and deliberately left open
at the `@`, so it matches both a `@refs/tags/v1.0.0` pin and a `@<sha>` pin.

`--certificate-github-workflow-repository` binds the claim to the repository the
image was built from. Without it, any repository in the organization using these
workflows would satisfy the identity check.

## Read the SBOM

```bash
cosign download attestation \
  --predicate-type https://cyclonedx.org/bom \
  "${IMAGE}@${AMD64}" \
  | jq -r '.payload | @base64d | fromjson | .predicate' \
  > sbom.cdx.json

# What is in the image?
jq -r '.components[] | "\(.name) \(.version)"' sbom.cdx.json | sort
```

SBOMs are also uploaded as workflow artifacts on every build, retained for 30
days, if you want them without pulling from the registry.

## Read the provenance

```bash
gh attestation verify oci://"${IMAGE}:v1.2.3" \
  --repo thingzio/my-app \
  --signer-workflow thingzio/actions/.github/workflows/build-ko.yaml \
  --format json \
  | jq '.[0].verificationResult.statement.predicate.buildDefinition'
```

The fields worth reading:

- `externalParameters.workflow` — the **caller's** workflow, the entry point.
- `resolvedDependencies` — the source repository and the exact commit built.
- `.builder.id` in `runDetails` — the **reusable workflow**, i.e. the build
  definition. This is what `--signer-workflow` matched.

## A note on the referrers API

`ghcr.io` does not implement the OCI 1.1 `/v2/<name>/referrers/<digest>`
endpoint; it answers `404 MANIFEST_UNKNOWN`. Attestations therefore land through
the specification's referrers **tag fallback** (`sha256-<hex>`).

This is transparent to `cosign`, `oras` and `gh`, which is why every command on
this page uses one of those rather than a raw registry API call. A direct
`curl` against the referrers endpoint will return nothing and is not evidence
that the attestation is missing.

## Verifying a binary

A release from [`release-go.yaml`](../.github/workflows/release-go.md) carries
one Sigstore signature over `checksums.txt` and SLSA provenance covering every
artifact that file names. One signature is enough because the checksum file
commits to each artifact by digest — and the workflow proves that correspondence
before signing, by re-deriving every digest from the artifacts on the release.

```bash
gh release download v1.2.3 --repo thingzio/my-app \
  -p 'checksums.txt' -p 'checksums.txt.bundle' -p '*_linux_amd64.tar.gz'

# 1. The checksum file was signed by the shared build definition.
cosign verify-blob checksums.txt \
  --bundle checksums.txt.bundle \
  --certificate-identity-regexp '^https://github\.com/thingzio/actions/\.github/workflows/release-go\.yaml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

# 2. The artifact you downloaded is one the signed file commits to.
sha256sum --check --ignore-missing checksums.txt
```

The identity is the point: the signer is **the reusable workflow**, not the
repository being released. Verifying without
`--certificate-identity-regexp` would accept a signature from anyone.

`--ignore-missing` is what lets step 2 work on a subset of the release. Without
it, `sha256sum` fails on every artifact you did not download.

Provenance is verified separately, and covers each artifact by name:

```bash
gh attestation verify my-app_1.2.3_linux_amd64.tar.gz \
  --repo thingzio/my-app \
  --signer-workflow thingzio/actions/.github/workflows/release-go.yaml
```

`--signer-workflow` does the same job here as for images: without it the check
passes for provenance signed by any workflow in the repository, including one an
attacker added.

SBOMs are attached as release assets when the caller's `.goreleaser.yaml` has an
`sboms:` block. They are covered by `checksums.txt` like any other artifact, so
step 2 verifies them too; they carry no separate attestation.

## Enforcing verification in Kubernetes

With [Sigstore Policy Controller](https://docs.sigstore.dev/policy-controller/overview/):

```yaml
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata:
  name: thingzio-built
spec:
  images:
    - glob: ghcr.io/thingzio/**
  authorities:
    - keyless:
        url: https://fulcio.sigstore.dev
        identities:
          # Only images built by the shared, reviewed build definitions.
          - issuer: https://token.actions.githubusercontent.com
            subjectRegExp: '^https://github\.com/thingzio/actions/\.github/workflows/build-(ko|docker)\.yaml@.*$'
      attestations:
        - name: must-have-sbom
          predicateType: https://cyclonedx.org/bom
```

The equivalent Kyverno policy uses `verifyImages` with the same
`subjectRegExp`.

## Troubleshooting

**`no attestations found`** — check you are verifying the right subject.
Provenance is on the index digest; the SBOM is on a platform digest. Verifying
an SBOM against the index will legitimately find nothing.

**`certificate identity did not match`** — the image was probably built by a
caller-owned workflow rather than one of these reusable workflows, or the
workflow file was renamed. The filename is part of the identity.

**`failed to verify certificate chain`** — a cosign older than v3.1.0 writes
the legacy Rekor `dsse` entry type, which `sigstore-go` cannot verify. These
workflows pin cosign at or above v3.1.0 for exactly this reason; check what
your local cosign is.
