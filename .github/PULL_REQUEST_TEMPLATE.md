<!--
Thanks for contributing. Nothing here is mandatory — delete what does not
apply. A short, clear description beats a fully filled-in template.
-->

## What this changes

<!-- What does this do, and why? If it fixes an issue, say "Fixes #123". -->

## How it was verified

<!--
What did you actually run? `make verify` is the usual answer. If a workflow
changed, link the selftest run that exercised it.
-->

## Notes for the reviewer

<!--
Optional. Trade-offs you weighed, alternatives you rejected, anything you are
unsure about, or parts you would especially like a second opinion on.
-->

---

- [ ] Commits are signed off (`git commit -s`) — see [CONTRIBUTING.md](../CONTRIBUTING.md#developer-certificate-of-origin)
- [ ] `make verify` passes
- [ ] Documentation updated, if this changes behavior someone depends on

<!--
If this touches .github/workflows/build-ko.yaml, build-docker.yaml, or anything
under .github/actions/ or scripts/, these apply too. They are the rules the
SLSA Build Level 3 claim rests on — see CONTRIBUTING.md.
-->

- [ ] No new input reaches a shell as code
- [ ] No new way for a caller to influence `runs-on`
- [ ] Caller data passed through `env:`, never interpolated into a `run:` body
- [ ] Every new `uses:` pinned to a commit SHA with a `# vX.Y.Z` comment
- [ ] The change is observable in `selftest.yaml`
