# Security policy

## Reporting a vulnerability

Report suspected vulnerabilities privately through
[GitHub Security Advisories](https://github.com/thingzio/actions/security/advisories/new).
Please do not open a public issue for a suspected vulnerability.

Include, where you can: the workflow or action affected, the commit or tag, a
description of the impact, and the smallest reproduction you have. A repository
or workflow file that triggers the behavior is more useful than a description of
it.

You should get an acknowledgement within three business days. We will tell you
whether we consider the report in scope, and keep you updated as a fix
progresses. Credit is offered by default in the advisory unless you ask
otherwise.

## Why this repository warrants care

Every repository in the organization delegates its container builds here. A
vulnerability in these workflows is not contained: it reaches the release
pipeline of everything that calls them, and from there the images their users
run. Treat findings here as supply-chain findings, not CI bugs.

The workflows run in the caller's context with `packages: write`,
`id-token: write` and `attestations: write`. They can publish images under the
caller's namespace and mint Sigstore certificates bound to the caller's
identity.

## Supported versions

Security fixes land on the latest major version. The floating `vN` tag moves on
release, so consumers tracking `@v1` receive fixes automatically; consumers
pinned to a commit SHA must bump, and Dependabot or Renovate will offer it.

Older majors receive fixes only for the duration of an announced deprecation
window (see [RELEASING.md](RELEASING.md#deprecating-a-workflow)).

## Scope

These workflows aim to let a consumer establish, independently:

- which exact bytes a published image tag refers to;
- that those bytes were produced by a reviewed, shared build definition rather
  than by arbitrary code in the calling repository;
- what that build consumed, as a CycloneDX SBOM bound to the manifest it
  describes; and
- that no release tag ever pointed at bytes lacking that evidence.

The following are in scope for a report:

- any input, context value, or repository content that reaches a shell as code
  inside a reusable workflow;
- any way for a caller to influence `runs-on`, and so the machine the build runs
  on;
- provenance or an SBOM attested to a subject that does not describe the bytes a
  consumer resolves — including an SBOM on an index rather than a platform
  manifest, or a digest the build did not produce;
- a release tag that can come to point at unattested bytes, including through a
  partial failure, a cancellation, or a re-run;
- a fork pull request obtaining a write credential, an OIDC token, or any
  repository secret;
- a tool, action, or base image that can be substituted without failing the
  checksum or digest pin that covers it;
- credential disclosure through logs, job summaries, step outputs, artifacts, or
  the built image; and
- a build that reports success while having published nothing, or having
  published something other than what it reports.

The following are **not** vulnerabilities in these workflows:

- a malicious or vulnerable commit in the calling repository. These workflows
  build what they are given, and a backdoored commit produces a valid, signed,
  Build Level 3 image. Provenance authenticates *what built it*, not whether the
  source is good. Branch protection and code review are the control for that;
- a Dockerfile in a consumer repository doing something undesirable inside its
  own build. It cannot reach the job's OIDC token, but it fully determines the
  contents of the resulting image;
- vulnerabilities in the dependencies of a built image. The SBOM enumerates
  them; it makes no claim that any of them is unexploitable;
- an image that fails a consumer's policy when the evidence is cryptographically
  valid and the policy did not require otherwise. A signature authenticates an
  identity and bytes; policy decides trust; and
- behavior of GitHub, Sigstore, or a registry that these workflows correctly
  reported.

## Security posture

- **No input becomes shell.** There is no `build_command`, `pre_build_script` or
  `post_steps` input, and there will not be. Caller data reaches a shell only
  through `env:`, never interpolated into a `run:` body. `ko_flags` is a closed
  allowlist.
- **`runs-on` is never caller-controlled.** Platforms map to runner labels
  through a closed allowlist, because a caller-chosen runner would defeat the
  isolation the SLSA Build Level 3 claim rests on.
- **Publishing is digest-first.** Builds push to a run-unique candidate tag and
  release tags move onto the digest only after attestation succeeds, so a failed
  or cancelled run cannot leave a published `latest`.
- **Digest checks fail closed.** Before anything is signed, every digest must be
  well-formed, each platform digest must differ from the index digest, and the
  platform digests must differ from each other. An SBOM's `bomFormat` is
  asserted before `cosign attest` can stamp a CycloneDX predicate type on it.
- **Nothing arrives unverified.** Every `uses:` is pinned to a commit SHA; every
  downloaded binary is checked against its project's published SHA-256 and
  deleted on mismatch. There is no `curl | bash` in this repository.
- **Forks get no credential.** `pull_request` only, never
  `pull_request_target`. A fork build degrades to no push, no signature, no
  OIDC, and says so.
- **Workflows cannot drift from their actions.** Each reusable workflow checks
  itself out at `job.workflow_sha`, so the composite actions it runs come from
  the same commit by construction.
