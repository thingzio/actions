# shellcheck shell=bash
#
# Helpers shared by every script and composite action in this repository.
# Source it; do not execute it.
#
#   . "${SCRIPT_DIR}/lib/common.sh"
#
# Everything here is POSIX-ish bash that runs on bash 3.2, because that is what
# ships with macOS and "local development equals CI" is only true if the same
# script runs in both places. No `mapfile`, no `declare -A`, no `${var,,}`.

# log writes to stderr so it never pollutes a script's stdout contract.
log() { printf '%s\n' "$*" >&2; }

# die, warn and notice emit GitHub Actions workflow commands. Outside Actions
# they are still readable plain text.
die() { printf '::error::%s\n' "$*" >&2; exit 1; }
warn() { printf '::warning::%s\n' "$*" >&2; }
notice() { printf '::notice::%s\n' "$*" >&2; }

# sha256_of prints the hex SHA-256 of a file. Linux has sha256sum, macOS has
# shasum; without this the same script gives different answers on the two.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "neither sha256sum nor shasum is available"
  fi
}

# fetch downloads a URL to a path. Retries cover the transient 5xx and reset
# connections that make CI flaky; --fail turns an HTTP error into a non-zero
# exit instead of a file containing an error page.
fetch() {
  curl --fail --silent --show-error --location \
    --retry 5 --retry-delay 2 --retry-all-errors --retry-max-time 60 \
    --output "$2" "$1"
}

# sha256_from_manifest extracts one checksum from a release checksums.txt.
#
# Requires exactly one match. Substring matching would let "syft_1.0_linux_amd64"
# also match "syft_1.0_linux_amd64.sbom", and silently verifying the wrong
# artifact's checksum is worse than not verifying at all, so this compares the
# whole filename field and fails on 0 or 2+ matches. A leading "*" (the binary
# marker some tools emit) is stripped before comparing.
sha256_from_manifest() {
  local manifest="$1" name="$2" matches count
  [ -r "${manifest}" ] || die "checksum manifest not readable: ${manifest}"
  matches="$(awk -v want="${name}" '
    { f = $NF; sub(/^\*/, "", f); if (f == want) print $1 }
  ' "${manifest}")"
  count="$(printf '%s' "${matches}" | grep -c . || true)"
  [ "${count}" = "1" ] ||
    die "expected exactly one checksum for '${name}' in $(basename "${manifest}"), found ${count}"
  printf '%s\n' "${matches}"
}

# download_verified fetches a URL and refuses to leave the file in place unless
# its SHA-256 matches. This is the only sanctioned way to bring a binary onto a
# runner: no `curl | bash`, no unverified tarballs.
download_verified() {
  local url="$1" dest="$2" want="$3" got
  case "${want}" in
    *[!a-f0-9]* | "") die "expected a lowercase hex sha256 for ${url}, got '${want}'" ;;
  esac
  [ "${#want}" = "64" ] || die "expected a 64-character sha256 for ${url}, got '${want}'"

  fetch "${url}" "${dest}" || die "download failed: ${url}"
  got="$(sha256_of "${dest}")"
  if [ "${got}" != "${want}" ]; then
    rm -f "${dest}"
    die "checksum mismatch for ${url}: want ${want}, got ${got}"
  fi
}

# require_no_newline rejects multi-line values. Every caller-supplied input flows
# into a shell variable or a GITHUB_OUTPUT line; a newline in either can forge an
# extra output or an extra command, so it is refused at the boundary.
require_no_newline() {
  case "$2" in
    *"
"* | *$'\r'*) die "${1} must not contain a newline" ;;
  esac
}

# require_set fails when a required value is empty.
require_set() {
  [ -n "${2-}" ] || die "${1} is required"
}

# normalize_dir collapses the "current directory" spellings to nothing and
# strips a leading "./" and any trailing "/" from anything else, so "." "./"
# and "" all mean the root, and "./api" "api" and "api/" are one directory.
#
# This exists because a caller-supplied directory of "." joined naively
# produces "src/./go.sum" -- a spelling the shell's -f test accepts and
# actions/cache rejects, which is how the Go module cache came to silently
# never restore for every caller using the default.
normalize_dir() {
  local dir="$1"
  case "${dir}" in
    '' | '.' | './') printf '' ;;
    *)
      dir="${dir#./}"
      printf '%s' "${dir%/}"
      ;;
  esac
}

# join_path composes only the non-empty segments, so no "." segment and no
# doubled slash can survive the join.
join_path() {
  local head="$1" tail="$2"
  if [ -z "${head}" ]; then
    printf '%s' "${tail}"
  elif [ -z "${tail}" ]; then
    printf '%s' "${head}"
  else
    printf '%s/%s' "${head}" "${tail}"
  fi
}

# emit_output appends a name=value pair to $GITHUB_OUTPUT, refusing values that
# could forge additional outputs. Falls back to stdout when run outside Actions
# so scripts stay testable.
emit_output() {
  local name="$1" value="$2"
  require_no_newline "output ${name}" "${value}"
  if [ -n "${GITHUB_OUTPUT-}" ]; then
    printf '%s=%s\n' "${name}" "${value}" >>"${GITHUB_OUTPUT}"
  else
    printf '%s=%s\n' "${name}" "${value}"
  fi
}

# emit_multiline_output writes a heredoc-delimited multi-line output. A value
# that contained the delimiter could close the heredoc early and forge the
# outputs that follow, so the delimiter is randomized and then checked against
# the value rather than assumed to be safe.
emit_multiline_output() {
  local name="$1" value="$2" delim
  delim="ghadelim_${RANDOM}${RANDOM}${RANDOM}${RANDOM}"
  case "${value}" in
    *"${delim}"*) die "generated delimiter collided with the value of ${name}" ;;
  esac
  if [ -n "${GITHUB_OUTPUT-}" ]; then
    {
      printf '%s<<%s\n' "${name}" "${delim}"
      printf '%s\n' "${value}"
      printf '%s\n' "${delim}"
    } >>"${GITHUB_OUTPUT}"
  else
    printf '%s<<%s\n%s\n%s\n' "${name}" "${delim}" "${value}" "${delim}"
  fi
}

# host_os and host_arch normalize uname output to the vocabulary release
# artifacts use.
host_os() {
  case "$(uname -s)" in
    Linux) printf 'linux\n' ;;
    Darwin) printf 'darwin\n' ;;
    *) die "unsupported operating system: $(uname -s)" ;;
  esac
}

host_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) printf 'amd64\n' ;;
    aarch64 | arm64) printf 'arm64\n' ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}
