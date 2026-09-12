# Maintainers

## Current maintainers

| Name | GitHub | Area |
|---|---|---|
| Mark Chmarny | [@mchmarny](https://github.com/mchmarny) | All |

This is a one-person project. Saying so plainly is more useful than a
governance structure that implies people who do not exist.

## What maintainers do

- Review and merge pull requests
- Triage issues
- Cut releases (see [RELEASING.md](RELEASING.md))
- Respond to security reports (see [SECURITY.md](SECURITY.md))

## What makes this repository different

Every other repository in the organization delegates its container builds here.
A change merged into `main` reaches other people's release pipelines, and from
there the images their users run. Two consequences for whoever holds this role:

- **A review here is a supply-chain review**, not a CI review. The questions
  that matter are whether an input can reach a shell, whether a runner label can
  be influenced, and whether anything can publish before it is attested.
- **The selftest is the gate, not the linter.** Do not merge a change to a
  reusable workflow whose effect the selftest cannot observe.

## Becoming a maintainer

There is no committee and no vote. A second maintainer gets added when someone
has been contributing substantively for a while and wants the responsibility —
in practice, several merged non-trivial pull requests, helpful issue triage, and
a demonstrated feel for the project's direction. Open an issue or reach out.

When that happens, this file gets a second row and
[CONTRIBUTING.md](CONTRIBUTING.md#project-governance) gets updated to describe
how two people make decisions.

## Contact

For anything that is not a security report, use
[GitHub Issues](../../issues). For security reports, follow
[SECURITY.md](SECURITY.md) — please do not open a public issue.
