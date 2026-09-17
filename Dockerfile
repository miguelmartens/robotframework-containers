# syntax=docker/dockerfile:1.19
#
# One Dockerfile, three shipped variants. Build with:
#
#   docker buildx build --target base     -t rf:base     .
#   docker buildx build --target browser  -t rf:browser  .
#   docker buildx build --target selenium -t rf:selenium .
#
# Every variant is FROM `common` and copies exactly one virtualenv, built from
# its own dependency group in uv.lock. `common` is therefore byte-identical
# across all three images, so a registry stores it once and a user who pulls two
# variants downloads it once.

##############################################################################
# common -- the OS layer every variant shares.
##############################################################################
FROM debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132 AS common

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:/opt/robotframework/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/home/robot \
    TZ=UTC \
    ROBOT_TESTS_DIR=/opt/robotframework/tests \
    ROBOT_REPORTS_DIR=/opt/robotframework/reports \
    ROBOT_WORK_DIR=/opt/robotframework/work \
    ROBOT_DEPENDENCY_DIR=/opt/robotframework/dependencies \
    ROBOT_THREADS=1 \
    ROBOT_RERUN_MAX_ROUNDS=0

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install --no-install-recommends --yes \
        ca-certificates \
        python3 \
        tini \
        tzdata

# A real account with a real home directory.
#
# Upstream runs `USER 1000:1000` against an image that has no matching
# /etc/passwd entry and no $HOME, then papers over it with `chmod 777` on a few
# directories. That is the single largest source of bug reports against it
# (#425, #410, #420, #424, #314, #476) and it is also why Selenium Manager
# fails there: its cache defaults to ~/.cache/selenium.
#
# The account belongs to group 0 and every writable directory is group-writable,
# so `--user=<any-uid>:0` works as well -- that is the OpenShift arbitrary-UID
# contract. /etc/passwd is group-writable so the entrypoint can synthesise an
# entry for an unknown UID at runtime.
RUN set -eux; \
    useradd --uid 1000 --gid 0 --home-dir "${HOME}" --create-home --shell /bin/bash robot; \
    mkdir -p "${HOME}" \
             "${ROBOT_TESTS_DIR}" \
             "${ROBOT_REPORTS_DIR}" \
             "${ROBOT_WORK_DIR}" \
             "${ROBOT_DEPENDENCY_DIR}" \
             /opt/robotframework/bin; \
    chown -R 1000:0 "${HOME}" /opt/robotframework; \
    chmod -R g=u "${HOME}" /opt/robotframework; \
    chmod g=u /etc/passwd

COPY --chmod=0755 src/entrypoint/rf-entrypoint /opt/robotframework/bin/rf-entrypoint

##############################################################################
# builder-common -- toolchain for building the variant virtualenvs.
# Compilers exist only here and never reach a runtime stage.
##############################################################################
FROM common AS builder-common

# Renovate's dockerfile manager picks up `COPY --from=<image>:<tag>` natively,
# so this needs no custom manager.
COPY --from=ghcr.io/astral-sh/uv:0.12.10 /uv /usr/local/bin/uv

ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_PYTHON=/usr/bin/python3 \
    UV_PYTHON_DOWNLOADS=never \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install --no-install-recommends --yes \
        build-essential \
        libffi-dev \
        libssl-dev \
        python3-dev

WORKDIR /src

##############################################################################
# venv-* -- one hash-pinned virtualenv per variant.
##############################################################################
FROM builder-common AS venv-base
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    uv sync --locked --no-default-groups --group base

FROM builder-common AS venv-browser
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    uv sync --locked --no-default-groups --group browser

FROM builder-common AS venv-selenium
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    uv sync --locked --no-default-groups --group selenium

##############################################################################
# base -- Robot Framework and the shared libraries. No browsers, no drivers.
##############################################################################
FROM common AS base

COPY --from=venv-base --chown=1000:0 /opt/venv /opt/venv

ARG VERSION=dev
ARG REVISION=unknown
ARG CREATED
LABEL org.opencontainers.image.title="robotframework-containers/base" \
      org.opencontainers.image.description="Robot Framework with the common libraries. No browsers." \
      org.opencontainers.image.source="https://github.com/miguelmartens/robotframework-containers" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"

USER 1000:0
WORKDIR /opt/robotframework/work
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/robotframework/bin/rf-entrypoint"]
CMD ["run"]

##############################################################################
# browser -- base plus Browser Library (Playwright) with Chromium.
#
# The [bb] extra pulls robotframework-browser-batteries, which ships a
# precompiled Node runtime as a wheel. No nodejs and no npm in the image.
##############################################################################
FROM common AS browser

COPY --from=venv-browser --chown=1000:0 /opt/venv /opt/venv

ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright

# Passed through to `rfbrowser install`. Empty by default, which installs the
# full Chromium (641 MB) *and* chromium-headless-shell (340 MB).
#
# Measured on arm64, bundled suites run against each build:
#   (empty)       1772 MB   PASS
#   --only-shell  1132 MB   PASS  -- drops the full browser, so no headed mode
#                                    and no video recording
#   --no-shell    1432 MB   FAIL  -- Browser Library's headless=True resolves
#                                    chromium_headless_shell/chrome-linux/headless_shell
#
# Default is the full install: least surprising, and headed debugging keeps
# working. Set --only-shell for a headless-only CI image and save 640 MB.
ARG PLAYWRIGHT_INSTALL_FLAGS=""

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}"; \
    apt-get update; \
    rfbrowser install --with-deps ${PLAYWRIGHT_INSTALL_FLAGS} chromium; \
    # `rfbrowser install` wraps the underlying `npx playwright install` in
    # contextlib.suppress(Exception), so a failed download still exits 0.
    # Without this check the image would ship with no browser and only fail
    # once someone ran a suite against it.
    #
    # Accept either binary so --only-shell builds are verified too.
    found="$(find "${PLAYWRIGHT_BROWSERS_PATH}" -maxdepth 3 -type f \
        \( -name chrome -o -name headless_shell \) -print -quit)"; \
    if [ -z "${found}" ]; then \
        echo "FATAL: rfbrowser install produced no Chromium binary under ${PLAYWRIGHT_BROWSERS_PATH}" >&2; \
        exit 1; \
    fi; \
    echo "verified Chromium at ${found}"; \
    chmod -R a+rX "${PLAYWRIGHT_BROWSERS_PATH}"

ARG VERSION=dev
ARG REVISION=unknown
ARG CREATED
LABEL org.opencontainers.image.title="robotframework-containers/browser" \
      org.opencontainers.image.description="Robot Framework with Browser Library (Playwright) and Chromium." \
      org.opencontainers.image.source="https://github.com/miguelmartens/robotframework-containers" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"

USER 1000:0
WORKDIR /opt/robotframework/work
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/robotframework/bin/rf-entrypoint"]
CMD ["run"]

##############################################################################
# selenium -- base plus SeleniumLibrary, Chrome and Firefox.
# Phase 2; the stage is a placeholder so the graph is complete.
##############################################################################
FROM common AS selenium

COPY --from=venv-selenium --chown=1000:0 /opt/venv /opt/venv

ENV SE_CACHE_PATH=/opt/selenium \
    SE_OFFLINE=true \
    SE_AVOID_BROWSER_DOWNLOAD=true

USER 1000:0
WORKDIR /opt/robotframework/work
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/robotframework/bin/rf-entrypoint"]
CMD ["run"]
