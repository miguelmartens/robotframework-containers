# robotframework-containers

Container images for running [Robot Framework](https://robotframework.org/) test suites.

A maintained successor to
[`ppodgorsek/docker-robot-framework`](https://github.com/ppodgorsek/docker-robot-framework),
which has had no commit, release or published image since November 2025.

## Variants

One image per job, rather than one image carrying five browser installations.
This is the split that upstream planned in
[#484](https://github.com/ppodgorsek/docker-robot-framework/issues/484) and never shipped.

| Variant    | Contains                                               | Use when                                       |
| ---------- | ------------------------------------------------------ | ---------------------------------------------- |
| `base`     | Robot Framework and the common libraries. No browsers. | API, database, SSH, file and data-driven tests |
| `browser`  | `base` plus Browser Library (Playwright) with Chromium | Web tests — the recommended default            |
| `selenium` | `base` plus SeleniumLibrary with Chrome and Firefox    | You have existing SeleniumLibrary suites       |

All variants are published for `linux/amd64` and `linux/arm64`, and both
architectures are tested in CI before anything is pushed.

> `selenium` is not published yet — the stage exists but is Phase 2. See
> [Status](#status).

## Quick start

```bash
docker run --rm \
  -v "$PWD/tests:/opt/robotframework/tests:ro" \
  -v "$PWD/reports:/opt/robotframework/reports" \
  ghcr.io/miguelmartens/robotframework-containers:browser
```

Reports land in `./reports` as `output.xml`, `log.html` and `report.html`.

You do **not** need `--shm-size=1g`. If you ever do, that is a bug — please report it.

### Docker or Podman

Both are supported and both are tested in CI. Swap `docker` for `podman` in any
command on this page.

`Containerfile` and `.containerignore` are symlinks to `Dockerfile` and
`.dockerignore`, so Podman and Buildah find them by their preferred names while
there is still only one file to maintain. Buildah handles the BuildKit
`--mount=type=cache` directives natively; Docker needs `buildx` for them.

The `:z` suffix on the volume mounts below is an SELinux shared-label request.
It matters on Fedora/RHEL hosts and is ignored everywhere else. `:Z` would also
work but relabels the host directory exclusively, which can break other tools
reading the same path.

#### Rootless Podman and the reports directory

Rootless Podman maps your user to container root, so the image's uid `1000`
lands on a _subuid_ that does not own your bind-mounted reports directory. The
run fails with a clear message rather than a stack trace, but it does fail. Map
your user onto the image's uid instead:

```bash
podman run --rm --userns=keep-id:uid=1000,gid=0 \
  -v "$PWD/tests:/opt/robotframework/tests:ro,z" \
  -v "$PWD/reports:/opt/robotframework/reports:z" \
  ghcr.io/miguelmartens/robotframework-containers:browser
```

Reports then come back owned by you. Measured on a rootless Linux host:

| Approach                          | Writes? | Reports owned by                    |
| --------------------------------- | ------- | ----------------------------------- |
| plain `podman run`                | no      | —                                   |
| `--userns=keep-id:uid=1000,gid=0` | yes     | you                                 |
| `:U` volume flag                  | yes     | **a subuid you cannot even delete** |

`:U` is the trap: it looks like the fix and leaves you with files you cannot
remove. This does not arise on macOS, where the Podman machine's virtiofs mount
maps ownership for you — only on Linux hosts, which is where CI runs.

### Compose

`compose.yaml` runs the suites with either engine and starts the static site the
browser suite needs:

```bash
docker compose run --rm base
docker compose run --rm browser

podman compose run --rm base
podman compose run --rm browser
```

Or through the Makefile, which takes `ENGINE=podman`:

```bash
make compose-browser
make compose-browser ENGINE=podman
```

The `browser` service waits on a healthcheck against the site rather than
racing it.

## Configuration

| Variable                    | Default                       | Description                                        |
| --------------------------- | ----------------------------- | -------------------------------------------------- |
| `ROBOT_TESTS_DIR`           | `/opt/robotframework/tests`   | Where suites are read from                         |
| `ROBOT_REPORTS_DIR`         | `/opt/robotframework/reports` | Where reports are written                          |
| `ROBOT_TEST_RUN_ID`         | _(empty)_                     | Subdirectory under the reports dir for this run    |
| `ROBOT_OPTIONS`             | _(empty)_                     | Extra `robot` arguments                            |
| `ROBOT_THREADS`             | `1`                           | Parallel processes; uses Pabot when greater than 1 |
| `PABOT_OPTIONS`             | _(empty)_                     | Extra `pabot` arguments                            |
| `ROBOT_RERUN_MAX_ROUNDS`    | `0`                           | Rerun rounds for failed tests; `0` disables        |
| `ROBOT_RERUN_REBOT_OPTIONS` | _(empty)_                     | Extra `rebot` arguments used when merging reruns   |
| `TZ`                        | `UTC`                         | Timezone                                           |

### Passing options with spaces

`ROBOT_OPTIONS` and `PABOT_OPTIONS` are parsed with Python's `shlex`, not by the
shell, so quoted values survive intact:

```bash
docker run --rm \
  -e ROBOT_OPTIONS='--variable "GREETING:hello world" --loglevel DEBUG' \
  ... ghcr.io/miguelmartens/robotframework-containers:browser
```

This has been broken upstream since 2019
([#194](https://github.com/ppodgorsek/docker-robot-framework/issues/194),
[#345](https://github.com/ppodgorsek/docker-robot-framework/issues/345),
[#353](https://github.com/ppodgorsek/docker-robot-framework/issues/353))
and cannot be fixed there without the same change.

You can also append arguments directly, which sidesteps quoting entirely:

```bash
docker run --rm ... IMAGE run --loglevel DEBUG --include smoke
```

### Running as another user

The image runs as uid `1000`, gid `0`. Any uid works as long as gid `0` is kept:

```bash
docker run --rm --user 4711:0 ... IMAGE
```

The entrypoint synthesises a `/etc/passwd` entry for unknown uids and falls back
to a writable `HOME` if the default one is not writable, so OpenShift's random-uid
model works out of the box. Mounted report directories must be writable by that
uid or by gid `0`; the entrypoint will not change permissions on a directory you
mounted.

### Hardening

The images run with a read-only root filesystem:

```bash
docker run --rm --read-only --tmpfs /tmp \
  --cap-drop=ALL --security-opt=no-new-privileges \
  -v "$PWD/tests:/opt/robotframework/tests:ro" \
  -v "$PWD/reports:/opt/robotframework/reports" \
  ghcr.io/miguelmartens/robotframework-containers:browser
```

Nothing is written outside `/tmp` and the mounted reports directory. This is
covered by a CI regression test.

### Running your own command

The image uses a real `ENTRYPOINT`, so setup still happens when you supply your
own command:

```bash
docker run --rm ... IMAGE robot --version
docker run --rm ... IMAGE sh -c 'echo "$HOME"'
```

Upstream ships a bare `CMD`, so orchestrators that override the command — Testkube,
Kubernetes, Jenkins agent pods — silently skip report setup entirely
([#489](https://github.com/ppodgorsek/docker-robot-framework/issues/489),
[#509](https://github.com/ppodgorsek/docker-robot-framework/issues/509)).

### Extra dependencies

Mount a `pip-requirements.txt` or a `pyproject.toml` at
`/opt/robotframework/` and it is installed before the run:

```bash
docker run --rm \
  -v "$PWD/requirements.txt:/opt/robotframework/pip-requirements.txt:ro" \
  ... IMAGE
```

This runs on **every** container start and needs network access at test time.
Extending the image is better:

```dockerfile
FROM ghcr.io/miguelmartens/robotframework-containers:browser
USER 0
RUN /opt/venv/bin/pip install --no-cache-dir robotframework-appiumlibrary
USER 1000:0
```

## Which library versions are in an image?

The lockfile (`uv.lock`) is the single source of truth, and every image carries an
SBOM. Rather than a hand-maintained table in this README that drifts out of date:

```bash
# From the running image
docker run --rm IMAGE /opt/venv/bin/pip list

# From the published attestation, without pulling the image
docker buildx imagetools inspect IMAGE --format '{{ json .SBOM }}'
```

### A smaller `browser` image

The `browser` image ships both the full Chromium and Playwright's
`chromium-headless-shell`, because that is what `headless=True` resolves to and
because headed debugging and video recording keep working. If you only ever run
headless in CI, rebuild with `--only-shell` and save 640 MB:

```bash
docker buildx build --target browser \
  --build-arg PLAYWRIGHT_INSTALL_FLAGS=--only-shell -t rf:browser-slim .
```

Measured on arm64, with the bundled suites run against each build:

| Build          | Size    | Bundled suites |
| -------------- | ------- | -------------- |
| default        | 1843 MB | pass           |
| `--only-shell` | 1203 MB | pass           |
| `--no-shell`   | smaller | **fail**       |

`--no-shell` is listed because it looks like the obvious saving and is not one:
Browser Library's `headless=True` resolves to
`chromium_headless_shell/chrome-linux/headless_shell`, which that flag omits.

### What is deliberately left out

**DataDriver's `xls` extra.** It pulls `pandas` and `numpy`, which measured
141 MB of a 277 MB virtualenv — more than half of it, so that spreadsheets can
be read. CSV-driven tests work without it. If you need Excel:

```dockerfile
FROM ghcr.io/miguelmartens/robotframework-containers:base
USER 0
RUN /opt/venv/bin/pip install --no-cache-dir 'robotframework-datadriver[xls]'
USER 1000:0
```

**pip.** Runtime dependency mounts are installed with `uv`, which is a single
static binary with nothing vendored. pip bundles its own copies of `msgpack`
and `setuptools` (`pip/_vendor/vendor.txt`), both with published advisories that
fail this project's CVE gate over code paths only pip itself uses. `uv` is also
far faster, which matters because that install runs on every container start.

## Tags

Full versions are **immutable** and never re-pushed. Upstream republished `4.0.0`
with different contents and broke users
([#423](https://github.com/ppodgorsek/docker-robot-framework/issues/423)).

| Tag                      | Moves? | Example                |
| ------------------------ | ------ | ---------------------- |
| `X.Y.Z-<variant>`        | never  | `1.0.0-browser`        |
| `X.Y-<variant>`          | yes    | `1.0-browser`          |
| `X-<variant>`            | yes    | `1-browser`            |
| `<variant>`              | yes    | `browser`              |
| `sha-<commit>-<variant>` | never  | `sha-a1b2c3d…-browser` |

For CI, pin by digest.

Images are rebuilt on the first of every month so OS security fixes ship even when
no dependency has changed.

### Verifying provenance

Images are signed with cosign (keyless) and carry SBOM and provenance attestations:

```bash
cosign verify ghcr.io/miguelmartens/robotframework-containers:browser \
  --certificate-identity-regexp='^https://github.com/miguelmartens/robotframework-containers/' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

## Migrating from ppodgorsek/docker-robot-framework

The environment-variable contract is unchanged, so most users only swap the image
reference. Differences to know about:

- **Pick a variant.** `ppodgorsek/robot-framework` bundled everything;
  `:browser` or `:selenium` replaces it.
- **No `SCREEN_WIDTH`/`SCREEN_HEIGHT`/`SCREEN_COLOUR_DEPTH`.** There is no Xvfb.
  Playwright runs headless natively; set the viewport in your suites instead.
- **No AWS S3 upload.** Use your CI's artifact step. S3-compatible upload is
  planned — see [Status](#status).
- **No `VOLUME` declaration** on the reports directory, so no surprise anonymous
  volumes. Bind-mount it yourself, as in the examples above.
- **Microsoft Edge is not included.** It is the subject of upstream's open
  [#546](https://github.com/ppodgorsek/docker-robot-framework/issues/546) and is
  why upstream's arm64 image silently ships without it. Playwright recommends
  Chromium for Edge-like scenarios on Linux.
- **`rflint` is not included.** It is unmaintained. Robocop is bundled instead
  and covers both linting and formatting
  ([#511](https://github.com/ppodgorsek/docker-robot-framework/issues/511)).

## Status

Phase 1 (this release): `base` and `browser`, multi-arch, tested in CI, signed.

Planned:

- Phase 2 — the `selenium` variant, with the Selenium Manager driver cache
  pre-warmed at build time so runs need no network.
- Phase 3 — release automation and published support policy.
- Phase 4 — a `lint` entrypoint, S3-compatible report upload
  ([#373](https://github.com/ppodgorsek/docker-robot-framework/issues/373)),
  a VNC debug endpoint
  ([#375](https://github.com/ppodgorsek/docker-robot-framework/issues/375)),
  and runtime corporate-CA injection
  ([#314](https://github.com/ppodgorsek/docker-robot-framework/issues/314)).

## Development

```bash
make install       # pinned Prettier from package-lock.json
make sync          # local .venv with the base dependency group
make hooks         # install the git hooks (once per clone)
make format        # Prettier for YAML/Markdown/JSON, Ruff for the entrypoint
make format-check  # verify without writing
make lint          # yamllint, Ruff, Robocop, hadolint, lockfile check
make build         # VARIANT=base|browser|selenium
make test
```

`make hooks` installs the pre-commit hooks, which include `no-commit-to-branch`
for `main` — work on a branch and open a PR. CI runs `make format-check` and the
same linters, so formatting is enforced rather than merely suggested.

Two dependency sets, two lockfiles: `uv.lock` for everything that ships in an
image, `package-lock.json` purely to pin Prettier for this repository.

> **Windows contributors:** `Containerfile` and `.containerignore` are git
> symlinks. Clone with `git config --global core.symlinks true` (or run an
> elevated/Developer Mode shell), otherwise they check out as text files
> containing the target name and `podman build` will fail. `docker build` is
> unaffected either way, since it reads `Dockerfile` directly.

Dependencies live in `pyproject.toml` as one group per variant, resolved into a
single hash-pinned `uv.lock`. Run `make lock` after changing them.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md)
for the setup, the design decisions worth knowing before changing them, and what
CI will check. Security reports go through [SECURITY.md](SECURITY.md).

## Licence

MIT — see [LICENSE](LICENSE). This project is an independent successor to
`ppodgorsek/docker-robot-framework` (Copyright © 2016 Paul Podgorsek), also MIT.
No source is copied verbatim; what carries over is the interface, so existing
users can migrate without rewriting their pipelines. See [NOTICE](NOTICE).
