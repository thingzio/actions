# `setup-go`

Configures the Go toolchain from the repository's own `go.mod`, and enables the
module cache only when a lock file actually exists.

```yaml
- uses: thingzio/actions/.github/actions/setup-go@<commit-sha>  # v1.3.0
```

That is the whole thing for a repository whose module is at the root. It
replaces a four-line local composite that every thingzio Go repository had its
own byte-identical copy of.

## Inputs

| Input | Default | Description |
|---|---|---|
| `go_version` | `''` | Explicit Go version. Empty reads `go_version_file`. |
| `go_version_file` | `go.mod` | File the Go version is read from, relative to `working_directory`. |
| `working_directory` | `.` | Directory containing the Go module. |
| `cache` | `true` | Enable the module cache, when a `go.sum` exists. |

## Outputs

| Output | Description |
|---|---|
| `module_directory` | Normalized module directory, safe to pass to `working-directory:` |

## Why the cache is conditional

`actions/setup-go` **fails outright** when module caching is on and it cannot
find a lock file. A module with no third-party dependencies legitimately has no
`go.sum`, so asking unconditionally turns a valid repository into a broken
build. This action decides before asking.

The path arithmetic is shared with the reusable workflows
(`scripts/actions/go-module-cache.sh`) rather than reimplemented, because it has
a sharp edge: a `working_directory` of `.` composed naively yields `./go.sum`,
which the shell's `-f` test accepts and `actions/cache` rejects with

```
Invalid pattern './go.sum'. Relative pathing '.' and '..' is not allowed.
```

The build still succeeds — slower, silently, forever. That bug shipped once
already; one implementation with tests is the fix.

## `module_directory`

Emitted because the two consumers have incompatible requirements:
`working-directory:` needs a non-empty value, so the repository root is `.`,
while `cache-dependency-path` is a glob that rejects a `.` segment, so there the
root is bare. Conflating them is what caused the bug above.

```yaml
- uses: thingzio/actions/.github/actions/setup-go@<commit-sha>  # v1.3.0
  id: go
  with:
    working_directory: api

- run: go test ./...
  working-directory: ${{ steps.go.outputs.module_directory }}
```

> **Composite actions are SLSA Build Level 2, not 3.** They run inside a job you
> control. Use a reusable workflow when the level matters.
