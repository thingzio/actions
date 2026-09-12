# shellcheck shell=bash
#
# Tests for scripts/check-goreleaser-config.sh.
#
# Every obligation this script enforces fails silently without it: the build is
# green, the release looks right, and the property that was lost -- a draft, a
# signature, a single release per tag -- is only discovered by whoever trusted
# it. So the cases that matter most are the ones where a plausible caller
# configuration is wrong in a way nothing else would report.

CHECK_SH="${REPO_ROOT}/scripts/check-goreleaser-config.sh"

# _config writes a .goreleaser.yaml from stdin into a fresh directory and runs
# the checker against it. Echoes the directory so a test can inspect it.
_config() {
  local dir
  dir="$(mktemp -d)"
  cat > "${dir}/.goreleaser.yaml"
  run bash "${CHECK_SH}" "${dir}"
}

_valid_config() {
  cat <<'EOF'
version: 2
builds:
  - id: app
    main: .
checksum:
  name_template: checksums.txt
release:
  draft: true
  use_existing_draft: true
  prerelease: auto
sboms:
  - artifacts: archive
EOF
}

## the shape a caller is required to have

test_accepts_a_conforming_config() {
  local dir
  dir="$(mktemp -d)"
  _valid_config > "${dir}/.goreleaser.yaml"
  run bash "${CHECK_SH}" "${dir}"
  assert_ok
}

test_accepts_keys_in_any_order() {
  _config <<'EOF'
version: 2
release:
  prerelease: auto
  use_existing_draft: true
  draft: true
sboms:
  - artifacts: archive
EOF
  assert_ok
}

test_accepts_a_quoted_boolean() {
  _config <<'EOF'
version: 2
release:
  draft: "true"
  use_existing_draft: 'true'
sboms:
  - artifacts: archive
EOF
  assert_ok
}

test_accepts_a_trailing_comment_on_the_value() {
  _config <<'EOF'
version: 2
release:
  draft: true   # invisible until the attest job has signed it
  use_existing_draft: true
sboms:
  - artifacts: archive
EOF
  assert_ok
}

## release.draft

# goreleaser's own default. A caller who does nothing lands here, which is why
# silence is not an acceptable answer.
test_rejects_a_config_with_no_draft() {
  _config <<'EOF'
version: 2
release:
  prerelease: auto
EOF
  assert_failed
  assert_stderr_contains "release.draft must be true"
}

test_rejects_draft_set_to_false() {
  _config <<'EOF'
version: 2
release:
  draft: false
  use_existing_draft: true
EOF
  assert_failed
  assert_stderr_contains "release.draft must be true"
}

test_rejects_a_config_with_no_release_block_at_all() {
  _config <<'EOF'
version: 2
builds:
  - id: app
EOF
  assert_failed
  assert_stderr_contains "release.draft must be true"
}

# A commented-out setting is the shape a half-finished migration leaves behind.
test_rejects_a_commented_out_draft() {
  _config <<'EOF'
version: 2
release:
  # draft: true
  prerelease: auto
EOF
  assert_failed
  assert_stderr_contains "release.draft must be true"
}

# Only a direct child of release: answers for release.draft. A deeper key that
# happens to share the name must not satisfy the requirement, or the check
# would pass on a configuration that does not set it.
test_does_not_accept_a_nested_key_of_the_same_name() {
  _config <<'EOF'
version: 2
release:
  header:
    draft: true
  use_existing_draft: true
EOF
  assert_failed
  assert_stderr_contains "release.draft must be true"
}

# Flow mappings are outside the subset this reads. Failing closed is the only
# safe answer: the alternative is reporting a draft that was never set.
test_fails_closed_on_a_flow_mapping() {
  _config <<'EOF'
version: 2
release: {draft: true, use_existing_draft: true}
EOF
  assert_failed
  assert_stderr_contains "release.draft must be true"
}

## release.use_existing_draft

test_rejects_a_config_without_use_existing_draft() {
  _config <<'EOF'
version: 2
release:
  draft: true
EOF
  assert_failed
  assert_stderr_contains "use_existing_draft"
}

test_explains_why_use_existing_draft_matters() {
  _config <<'EOF'
version: 2
release:
  draft: true
EOF
  assert_failed
  assert_stderr_contains "second draft for the same tag"
}

## release.disable

test_rejects_a_disabled_release() {
  _config <<'EOF'
version: 2
release:
  disable: true
  draft: true
  use_existing_draft: true
EOF
  assert_failed
  assert_stderr_contains "release.disable"
}

## signs

# The workflow passes --skip=sign, so a leftover block is not a competing
# signature: it is no signature, believed to be one.
test_rejects_a_leftover_signs_block() {
  _config <<'EOF'
version: 2
release:
  draft: true
  use_existing_draft: true
signs:
  - cmd: cosign
    args: ['sign-blob', '${artifact}']
EOF
  assert_failed
  assert_stderr_contains "remove the signs block"
}

test_does_not_confuse_docker_signs_with_signs() {
  _config <<'EOF'
version: 2
release:
  draft: true
  use_existing_draft: true
docker_signs:
  - cmd: cosign
sboms:
  - artifacts: archive
EOF
  assert_ok
}

## sboms

# A warning, not a failure: a caller may legitimately not want SBOMs. Silence
# would be worse, because the workflow installs syft either way and the
# documentation advertises the capability.
test_warns_but_succeeds_without_an_sboms_block() {
  _config <<'EOF'
version: 2
release:
  draft: true
  use_existing_draft: true
EOF
  assert_ok
  assert_stderr_contains "no sboms block"
}

## reporting

# One run should report every problem. Fixing them one CI round-trip at a time
# is the difference between a five-minute migration and an hour of them.
test_reports_every_problem_in_one_run() {
  _config <<'EOF'
version: 2
signs:
  - cmd: cosign
EOF
  assert_failed
  assert_stderr_contains "release.draft must be true"
  assert_stderr_contains "use_existing_draft"
  assert_stderr_contains "remove the signs block"
}

## locating the config

test_finds_a_yml_config() {
  local dir
  dir="$(mktemp -d)"
  _valid_config > "${dir}/.goreleaser.yml"
  run bash "${CHECK_SH}" "${dir}"
  assert_ok
}

test_finds_an_undotted_config() {
  local dir
  dir="$(mktemp -d)"
  _valid_config > "${dir}/goreleaser.yaml"
  run bash "${CHECK_SH}" "${dir}"
  assert_ok
}

test_rejects_a_directory_with_no_config() {
  local dir
  dir="$(mktemp -d)"
  run bash "${CHECK_SH}" "${dir}"
  assert_failed
  assert_stderr_contains "no goreleaser configuration"
}

test_rejects_a_missing_directory() {
  run bash "${CHECK_SH}" "/nonexistent/${RANDOM}"
  assert_failed
}

test_requires_a_directory_argument() {
  run bash "${CHECK_SH}"
  assert_failed
}

## the shipped fixture

# testdata/go-app is what the selftest builds, and it is the example a caller
# copies. If it ever stops satisfying the checker, the documentation is wrong.
test_the_selftest_fixture_satisfies_the_checker() {
  run bash "${CHECK_SH}" "${REPO_ROOT}/testdata/go-app"
  assert_ok
}
