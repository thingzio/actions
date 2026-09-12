# shellcheck shell=bash
#
# Tests for scripts/actions/go-module-cache.sh.
#
# The reason this file exists: with the default working_directory of ".", the
# lock-file path was composed as "src/./go.sum". The shell `-f` test accepts
# that spelling, so the step reported cache=true, and actions/cache then
# rejected the pattern at restore time:
#
#   Invalid pattern 'src/./go.sum'. Relative pathing '.' and '..' is not allowed.
#
# Nothing failed. The build succeeded, slower, for every caller using the
# default -- which is all of them. The interesting cases below are therefore the
# spellings of "the checkout root" and the ways a subdirectory can be written.

GO_MODULE_CACHE_SH="${REPO_ROOT}/scripts/actions/go-module-cache.sh"

# _run executes the script with a clean environment so a variable left over from
# the developer's shell cannot influence a test.
_run() {
  env -i \
    PATH="${PATH}" \
    HOME="${HOME}" \
    "$@" \
    bash "${GO_MODULE_CACHE_SH}"
}

# _mkcheckout creates a checkout tree, optionally with a go.sum at a subpath.
_mkcheckout() {
  local root sub="${1-}"
  root="$(mktemp -d)"
  mkdir -p "${root}/src${sub:+/$sub}"
  printf 'h1:fake\n' >"${root}/src${sub:+/$sub}/go.sum"
  printf '%s' "${root}"
}

test_default_working_directory_has_no_dot_segment() {
  local root out
  root="$(_mkcheckout)"
  out="$(cd "${root}" && _run CHECKOUT_DIR=src WORKING_DIRECTORY=.)"
  assert_contains "${out}" 'path=src/go.sum' \
    'a working_directory of "." must not produce src/./go.sum'
  assert_contains "${out}" 'cache=true' 'go.sum present means the cache is usable'
  assert_contains "${out}" 'dir=src' 'the module directory is the checkout root'
  rm -rf "${root}"
}

test_empty_working_directory_behaves_as_root() {
  local root out
  root="$(_mkcheckout)"
  out="$(cd "${root}" && _run CHECKOUT_DIR=src WORKING_DIRECTORY=)"
  assert_contains "${out}" 'path=src/go.sum' 'an empty working_directory is the checkout root'
  rm -rf "${root}"
}

test_dot_slash_working_directory_behaves_as_root() {
  local root out
  root="$(_mkcheckout)"
  out="$(cd "${root}" && _run CHECKOUT_DIR=src WORKING_DIRECTORY=./)"
  assert_contains "${out}" 'path=src/go.sum' '"./" is the checkout root'
  rm -rf "${root}"
}

test_subdirectory_is_preserved() {
  local root out
  root="$(_mkcheckout api)"
  out="$(cd "${root}" && _run CHECKOUT_DIR=src WORKING_DIRECTORY=api)"
  assert_contains "${out}" 'path=src/api/go.sum' 'a subdirectory module keeps its path'
  assert_contains "${out}" 'dir=src/api' 'the module directory includes the subdirectory'
  rm -rf "${root}"
}

test_leading_dot_slash_on_subdirectory_is_stripped() {
  local root out
  root="$(_mkcheckout api)"
  out="$(cd "${root}" && _run CHECKOUT_DIR=src WORKING_DIRECTORY=./api)"
  assert_contains "${out}" 'path=src/api/go.sum' '"./api" and "api" are the same module'
  rm -rf "${root}"
}

test_trailing_slash_does_not_double() {
  local root out
  root="$(_mkcheckout api)"
  out="$(cd "${root}" && _run CHECKOUT_DIR=src WORKING_DIRECTORY=api/)"
  assert_contains "${out}" 'path=src/api/go.sum' 'a trailing slash must not produce src/api//go.sum'
  rm -rf "${root}"
}

test_missing_go_sum_disables_the_cache() {
  local root out
  root="$(mktemp -d)"
  mkdir -p "${root}/src"
  out="$(cd "${root}" && _run CHECKOUT_DIR=src WORKING_DIRECTORY=. 2>/dev/null)"
  assert_contains "${out}" 'cache=false' 'no go.sum means the cache is disabled'
  assert_contains "${out}" 'path=' 'no go.sum means no dependency path'
  rm -rf "${root}"
}

test_no_emitted_path_contains_a_dot_segment() {
  # The regression guard, stated directly: whatever the caller writes, the
  # emitted path must never contain a "." or ".." segment, because
  # actions/cache rejects both.
  local root out spelling
  root="$(_mkcheckout api)"
  for spelling in '.' './' '' 'api' './api' 'api/'; do
    out="$(cd "${root}" && _run CHECKOUT_DIR=src WORKING_DIRECTORY="${spelling}" 2>/dev/null)"
    assert_not_contains "${out}" '/./' \
      "working_directory '${spelling}' produced a '.' path segment"
    assert_not_contains "${out}" '/../' \
      "working_directory '${spelling}' produced a '..' path segment"
    assert_not_contains "${out}" '//' \
      "working_directory '${spelling}' produced a doubled slash"
  done
  rm -rf "${root}"
}
