# Entry point for local development. Every target here is the same command the
# `ci` workflow runs, reading the same pinned versions from .versions.yaml, so a
# green `make verify` on a laptop means a green CI run.
#
# Tools are installed into ./.bin (gitignored) rather than system-wide, so this
# repository can never be linted by whatever version happens to be on $PATH.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

BIN := $(CURDIR)/.bin
VERSIONS := $(CURDIR)/scripts/versions.sh
export PATH := $(BIN):$(PATH)

ACTIONLINT_VERSION := $(shell $(VERSIONS) tools.actionlint)
YAMLLINT_VERSION := $(shell $(VERSIONS) tools.yamllint)

.PHONY: help
help: ## Show this help
	@awk 'BEGIN { FS = ":.*## " } \
		/^[a-zA-Z0-9_-]+:.*## / { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 } \
		/^## / { printf "\n%s\n", substr($$0, 4) }' $(MAKEFILE_LIST)
	@printf '\n'

## Verification

.PHONY: verify
verify: lint test ## Run every check CI runs

.PHONY: test
test: ## Run the shell test suite
	@./test/run.sh

.PHONY: test-offline
test-offline: ## Run the shell test suite, skipping tests that need the network
	@THINGZ_SKIP_NETWORK_TESTS=1 ./test/run.sh

.PHONY: lint
lint: lint-actions lint-yaml lint-shell ## Run every linter

.PHONY: lint-actions
lint-actions: $(BIN)/actionlint ## Lint workflows and composite actions
	@actionlint -color

.PHONY: lint-yaml
lint-yaml: $(BIN)/yamllint ## Lint YAML formatting
	@yamllint --strict .

.PHONY: lint-shell
lint-shell: ## Lint shell scripts
	@command -v shellcheck >/dev/null 2>&1 || { \
		printf 'shellcheck not found. Install it with:\n'; \
		printf '  macOS:  brew install shellcheck\n'; \
		printf '  Ubuntu: apt-get install -y shellcheck (preinstalled on GitHub runners)\n'; \
		exit 1; \
	}
	@find scripts test -name '*.sh' -type f -print0 \
		| sort -z \
		| xargs -0 shellcheck --severity=style --external-sources

## Tooling

.PHONY: tools
tools: $(BIN)/actionlint $(BIN)/yamllint ## Install every pinned tool into ./.bin

$(BIN)/actionlint:
	@./scripts/install-tool.sh actionlint $(ACTIONLINT_VERSION) $(BIN)

# yamllint is a Python package, so it gets a dedicated virtualenv rather than a
# `pip install --user` that would depend on the developer's global environment.
$(BIN)/yamllint:
	@python3 -m venv $(BIN)/venv
	@$(BIN)/venv/bin/pip install --quiet --disable-pip-version-check \
		yamllint==$(YAMLLINT_VERSION)
	@ln -sf $(BIN)/venv/bin/yamllint $(BIN)/yamllint

.PHONY: versions
versions: ## Print every pinned version
	@printf '%-12s %s\n' \
		ko         "$$($(VERSIONS) tools.ko)" \
		crane      "$$($(VERSIONS) tools.crane)" \
		syft       "$$($(VERSIONS) tools.syft)" \
		cosign     "$$($(VERSIONS) tools.cosign)" \
		actionlint "$$($(VERSIONS) tools.actionlint)" \
		yamllint   "$$($(VERSIONS) tools.yamllint)"

.PHONY: clean
clean: ## Remove installed tools
	@rm -rf $(BIN)
