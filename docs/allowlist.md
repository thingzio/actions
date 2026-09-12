# Organization Actions policy

What a consuming organization or repository must permit for these workflows to
run. If your Actions policy is **"Allow all actions and reusable workflows"**,
nothing here applies — skip to [Recommended settings](#recommended-settings).

## If you use "Allow enterprise/organization, and select non-organization…"

Add the patterns below under
**Settings → Actions → General → Allow specified actions and reusable
workflows**.

The workflows do not run actions on your behalf beyond this list. Every entry
is pinned to a commit SHA inside this repository; the patterns below only tell
GitHub which publishers are permitted, since the allowlist does not accept SHAs.

```text
thingzio/*,
actions/checkout@*,
actions/setup-go@*,
actions/upload-artifact@*,
actions/attest-build-provenance@*,
sigstore/cosign-installer@*,
docker/login-action@*,
docker/setup-buildx-action@*,
docker/build-push-action@*
```

Narrower than it looks: `thingzio/*` covers the reusable workflows and the
composite actions they call. The rest are the first-party and Docker-maintained
actions those composites use.

If you also want this repository's own CI patterns in your consumer repos, add:

```text
github/codeql-action/*,
ossf/scorecard-action@*,
zizmorcore/zizmor-action@*
```

## Access to this repository

`thingzio/actions` is **public**, so no access configuration is needed and the
default `GITHUB_TOKEN` can read it. That matters more than it looks: each
reusable workflow checks out its own repository at its own commit to reach its
composite actions, and a private build-definition repository would require every
consumer to supply a token with cross-repository read access.

If this repository is ever made private or internal, set
**Settings → Actions → General → Access** on *this* repository to
"Accessible from repositories in the organization", and expect the self-checkout
step to need a token.

## Recommended settings

For every repository consuming these workflows:

**Settings → Actions → General**

| Setting | Value | Why |
|---|---|---|
| Workflow permissions | **Read repository contents and packages permissions** | The workflows declare the writes they need per job. A read-only default means a workflow that forgets to is caught immediately rather than running over-privileged. |
| Allow GitHub Actions to create and approve pull requests | **off** | Closes a self-approval path to `main`. |
| Fork pull request workflows from outside collaborators | **Require approval for first-time contributors** (or all) | These workflows never expose a secret to a fork, but this limits free compute spent on drive-by pull requests. |

**Settings → Code security**

Enable Dependabot alerts, Dependabot security updates, secret scanning with push
protection, and private vulnerability reporting.

## Keeping the pin current

Pin to a commit SHA with a trailing version comment:

```yaml
uses: thingzio/actions/.github/workflows/build-ko.yaml@1a2b3c4…  # v1.0.0
```

Both Renovate and Dependabot understand this form and will raise bump pull
requests that update the SHA and the comment together.

Dependabot needs no extra configuration beyond the `github-actions` ecosystem:

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    groups:
      actions:
        patterns: ['*']
```
