.PHONY: help install lock sync format format-check lint lint-check \
        hooks hooks-run hooks-update build test clean

YAMLLINT ?= yamllint
PRECOMMIT ?= pre-commit
RUFF_VERSION ?= 0.15.4

VARIANT ?= browser
IMAGE ?= rfc:$(VARIANT)
PLATFORM ?= linux/$(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

ENTRYPOINT := src/entrypoint/rf-entrypoint

# Default target: show available commands
help:
	@echo "Available targets:"
	@echo "  make install         - Install the pinned tooling from package-lock.json"
	@echo "  make lock            - Regenerate uv.lock from pyproject.toml"
	@echo "  make sync            - Create a local .venv with the base dependency group"
	@echo "  make format          - Format all files with Prettier and Ruff"
	@echo "  make format-check    - Check formatting without modifying files"
	@echo "  make lint            - Lint YAML, Python, the Dockerfile and the suites"
	@echo "  make lint-check      - Lint everything (for CI)"
	@echo "  make hooks           - Install the git hooks from .pre-commit-config.yaml"
	@echo "  make hooks-run       - Run every pre-commit hook over the whole tree"
	@echo "  make hooks-update    - Bump the pinned hook revisions (Renovate does this too)"
	@echo "  make build           - Build one image  (VARIANT=base|browser|selenium)"
	@echo "  make test            - Run the bundled suites against that image"
	@echo "  make clean           - Remove the local venv, reports and caches"

# Install the pinned Prettier version
install:
	npm ci

# Restore dependencies whenever the lockfile is newer than node_modules
node_modules: package-lock.json
	npm ci
	@touch node_modules

# Python dependencies are locked separately, by uv
lock:
	uv lock

sync:
	uv sync --locked --no-default-groups --group base

# Format YAML/Markdown/JSON with Prettier and the entrypoint with Ruff
format: node_modules
	npm run format
	uvx ruff@$(RUFF_VERSION) format $(ENTRYPOINT)

# Verify formatting (useful for CI)
format-check: node_modules
	npm run format:check
	uvx ruff@$(RUFF_VERSION) format --check $(ENTRYPOINT)

# Lint everything this repo actually contains. There are no shell scripts here,
# so Ruff stands where shellcheck would.
lint:
	uv lock --check
	$(YAMLLINT) .
	uvx ruff@$(RUFF_VERSION) check $(ENTRYPOINT)
	uv run --no-default-groups --group base robocop check tests/
	@command -v hadolint >/dev/null 2>&1 \
		&& hadolint Dockerfile \
		|| echo "hadolint not installed; skipping Dockerfile lint"

# Lint everything (useful for CI)
lint-check: lint

# Install the git hooks (pre-commit itself lives outside this repo:
# `uv tool install pre-commit`, brew or pipx)
hooks:
	$(PRECOMMIT) install

# Run every hook over the whole tree, not just the files a commit touches
hooks-run:
	$(PRECOMMIT) run --all-files

# Bump the pinned hook revisions (Renovate does this too)
hooks-update:
	$(PRECOMMIT) autoupdate

build:
	docker buildx build --target $(VARIANT) --platform $(PLATFORM) --load -t $(IMAGE) .

# Deliberately no --shm-size=1g: the image has to work at the default.
test: build
	mkdir -p reports
	docker run --rm \
		-v "$(CURDIR)/tests/base:/opt/robotframework/tests:ro" \
		-v "$(CURDIR)/reports:/opt/robotframework/reports" \
		$(IMAGE)

clean:
	rm -rf .venv node_modules reports reports-* .ruff_cache .robocop_cache .pabotsuitenames
