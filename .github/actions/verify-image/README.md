# `verify-image`

Verifies that an image carries the provenance and SBOM attestations these
workflows produce, and that they were signed by the expected build definition.

This is the consumer-facing contract expressed as code. The selftest runs it
against every image it builds, so the commands published in
[docs/verification.md](../../../docs/verification.md) are proven on every pull
request rather than documented and left to rot — which has already caught one
wrong command.

## Usage

```yaml
- uses: thingzio/actions/.github/actions/verify-image@<sha>  # v1.0.0
  with:
    image_ref: ghcr.io/thingzio/my-app@sha256:...
    signer_workflow: .github/workflows/build-ko.yaml
    platform_digests: ${{ needs.image.outputs.platform_digests }}
```

Requires `cosign` on `PATH` for the SBOM check, and a registry login.

## Inputs

| Input | Default | Description |
|---|---|---|
| `image_ref` | *required* | `<image>@<digest>`. Must be digest-pinned. |
| `signer_workflow` | *required* | Path of the reusable workflow that signed, e.g. `.github/workflows/build-ko.yaml`. |
| `signer_repo` | `thingzio/actions` | `owner/repo` containing that workflow. |
| `repo` | current repository | `owner/repo` that owns the attestation, i.e. the caller. |
| `platform_digests` | `{}` | JSON object of platform → child digest. When set, each platform's CycloneDX attestation is verified too. |
| `github_token` | `github.token` | Token the GitHub CLI uses to fetch attestations. |

## What it checks

**Provenance**, via `gh attestation verify`. `--repo` says where the attestation
is stored (always the caller); `--signer-workflow` asserts who signed it (always
the reusable workflow). Trusting the caller for storage but the signer for
identity is the point: a consumer cannot mint provenance claiming this build
definition produced their image.

`signer_repo` and `signer_workflow` are joined into the single
`--signer-workflow` value gh expects — the two flags are mutually exclusive.

**SBOM**, via `cosign verify-attestation`, pinned to each platform manifest. The
certificate identity is the reusable workflow's `job_workflow_ref`, which Fulcio
records as the Build Signer URI (OID `1.3.6.1.4.1.57264.1.9`) and as the
certificate SAN. The regexp is anchored on the workflow path and left open at
the `@`, so it matches both a `@refs/tags/vX.Y.Z` pin and a `@<sha>` pin, and
regexp metacharacters in the supplied path are escaped so a workflow filename
cannot widen the match.
