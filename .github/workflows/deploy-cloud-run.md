# `deploy-cloud-run.yaml`

Deploys already-published, digest-pinned images to Cloud Run services and jobs,
optionally pausing a Cloud Scheduler job around the rollout.

It **builds nothing**. It takes the immutable references a build workflow
produced, validates them, and points Cloud Run at them.

## Usage

```yaml
jobs:
  build:
    uses: thingzio/actions/.github/workflows/build-ko.yaml@<commit-sha>  # v1.4.0
    with:
      image: thingzio/my-app
      main: ./cmd/my-app

  deploy:
    needs: build
    permissions:
      contents: read
      id-token: write
    uses: thingzio/actions/.github/workflows/deploy-cloud-run.yaml@<commit-sha>  # v1.4.0
    with:
      region: ${{ vars.REGION }}
      project_id: ${{ vars.PROJECT_ID }}
      workload_identity_provider: ${{ vars.WIF_PROVIDER }}
      service_account: ${{ vars.DEPLOYER_SA }}
      targets: |
        service=my-serve=${{ needs.build.outputs.image_ref }}
```

## Inputs

| Input | Default | Description |
|---|---|---|
| `targets` | — | Newline-separated `<service\|job>=<name>=<image@digest>` entries. **Required.** |
| `region` | — | Cloud Run region. **Required.** |
| `project_id` | — | GCP project ID. **Required.** |
| `workload_identity_provider` | — | WIF provider resource name. **Required.** |
| `service_account` | — | Deployer service account email. **Required.** |
| `environment` | `saas` | GitHub environment the job runs in. |
| `expected_registry` | `ghcr.io` | Registry the images must have been published to. |
| `remote_repository` | `gh` | Artifact Registry remote repository fronting that registry. |
| `scheduler_job` | `''` | Cloud Scheduler job to pause during the rollout. Empty disables it. |
| `resume_on_failure` | `true` | Resume the scheduler even when the rollout failed. `false` is fail-closed. |
| `timeout_minutes` | `20` | Job timeout. |

## `targets`

One line per resource, deployed **in the order given**:

```yaml
      targets: |
        # Delivery consumes what serve produces. Update the backward-compatible
        # consumer before the producer.
        job=devradar-saas-deliver=${{ needs.build-deliver.outputs.image_ref }}
        job=devradar-saas-scan=${{ needs.build-scan.outputs.image_ref }}
        service=devradar-saas-serve=${{ needs.build-serve.outputs.image_ref }}
```

Order is part of the contract and is covered by a test. Blank lines and `#`
comments are ignored, so the list can explain itself.

## Why images are rewritten

Cloud Run will only pull from Artifact Registry. Images published to `ghcr.io`
are fetched through an Artifact Registry **remote repository**:

```
ghcr.io/thingzio/my-app@sha256:abc…
  ↓
us-west1-docker.pkg.dev/<project>/gh/thingzio/my-app@sha256:abc…
```

That is a path rewrite, **not a copy**. The remote repository is a pull-through
cache and the digest is identical on the far side, so the bytes deployed are the
bytes that were built, signed and attested. The doubled organization segment is
correct: the proxy is common-upstream, so the full upstream path follows the
repository name.

## What is refused

Validation happens in `scripts/actions/deploy-targets.sh`, **before**
authenticating — a malformed target fails without having minted a production
credential.

| Refused | Why |
|---|---|
| A tag (`:v1.2.3`) | A tag can move between the build and the deploy, and then the thing that was tested is not the thing that ships. |
| A short or non-hex digest | It is not a digest. |
| An image from another registry | The check is anchored to where the build publishes; that is what makes it mean anything. |
| A name starting with `-` | It would be read by gcloud as a flag. |
| A name with a shell metacharacter | It reaches a command line. |
| An empty target list | Deploying nothing is a mistake, not a no-op. |

## The scheduler

Set `scheduler_job` to pause a Cloud Scheduler job for the duration of a
rollout:

```yaml
      scheduler_job: devradar-saas-deliver-scheduled
```

**Resume runs under `always()`.** This is the important part: a failed deploy
leaves the previous revision serving, which is visible and safe, but a scheduler
left paused stops scheduled work that nothing is watching — and the symptom
appears hours later as "why did nothing run overnight".

### Fail-closed

Set `resume_on_failure: false` where a partially updated set must not be
exercised until an operator has looked at it:

```yaml
      scheduler_job: my-scheduled-job
      resume_on_failure: false
```

A successful rollout still resumes. A failed one deliberately leaves the job
paused.

Choose this deliberately. It trades a silent stop for a guarantee, and the
silent stop is the one nobody gets paged for. It is worth it when a partial
rollout is genuinely unsafe to exercise; it is not worth it when the deploy
order already makes every prefix safe.

Resume is therefore deliberately forgiving. It may be reached when the pause
never happened, when authentication failed, or when the deploy died halfway;
resuming an already-enabled job is a no-op, and an unreadable state warns rather
than failing, so it cannot mask the real error. The one case it shouts about is
a scheduler that is paused and will not resume:

```
::error::could not resume <job> in <region> -- RESUME IT BY HAND
```

## Notes and gotchas

- **No rollback.** A failed `gcloud run services update` leaves the previous
  revision serving, which is the safe outcome; the rollout stops at the first
  failure rather than continuing. Recovering forward is deliberate.
- **This workflow is not covered by the selftest**, which would need a
  disposable GCP project and a real deploy. Its decision logic is unit tested
  with gcloud stubbed, and it is exercised for real by its consumers.

  Cloud Run absorbs much of what that gap would otherwise mean for a
  **service**: a revision that fails to start never receives traffic, so the
  previous revision keeps serving. The residual risk is narrower than "untested
  deploy" suggests, and sits in three places — **jobs**, which have no traffic
  routing and simply break on their next execution; a **healthy but wrong**
  image, since Cloud Run validates that a revision starts, not that it is the
  image you meant, which is why the digest check runs before authentication;
  and the **scheduler** pause/resume, which is this workflow's own logic and
  has no Cloud Run safety net at all.
- **Renaming this file is a breaking change** for anyone pinning it.
