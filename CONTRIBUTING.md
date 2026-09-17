# Contributing

Thanks for looking. Issues and pull requests are welcome, including "this
doesn't work on my setup" reports — those are how the Podman and rootless
behaviour got fixed.

## Getting set up

You need `git`, `make`, an OCI engine (Docker with `buildx`, or Podman),
[`uv`](https://docs.astral.sh/uv/) and Node.js. Then:

```bash
make install   # pinned Prettier, from package-lock.json
make sync      # local .venv with the base dependency group
make hooks     # install the pre-commit hooks
make help      # everything else
```

`make hooks` is worth doing: the hooks catch formatting and lint problems before
CI does, and CI runs the same checks.

## Branches

| Branch                  | What it is                                                                     |
| ----------------------- | ------------------------------------------------------------------------------ |
| `main`                  | Released code only. Receives merges from `develop` and nothing else. Protected |
| `develop`               | Integration. Everything lands here first. Protected                            |
| `feature/*`, `fix/*`, … | Your work. Branch from `develop`, PR back into `develop`                       |

Neither `main` nor `develop` accepts a direct push. Both require a pull request
with CI green; neither requires an approving review, so you can merge your own
work while the project has one maintainer.

```text
feature/x ──PR──► develop ──release PR──► main ──Release Please──► v0.2.0
                     │                                                 │
                     └── CI only, nothing published                    └── images published
```

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/), enforced in two
places: a `commit-msg` hook locally, and a check on the pull request title,
because feature branches are **squash-merged** and the PR title becomes the
commit on `develop`.

```text
feat(browser): install chromium with --only-shell by default
fix: keep quoted values in ROBOT_OPTIONS
deps: bump robotframework to 7.5.1
```

`feat` bumps the minor version, `fix` and `perf` the patch. A `!` after the type
or a `BREAKING CHANGE:` footer bumps the major. Anything else — `ci`, `chore`,
`refactor`, `test`, `style` — is released but hidden from the changelog.

Getting this wrong does not just look untidy: Release Please computes the next
version and the changelog from these messages, so a mislabelled commit is a
change that silently never appears in a release.

## Working on a change

> GitHub opens new pull requests against `main` by default, because that is the
> repository's default branch. Change the base to `develop` — the `main` ruleset
> only accepts merge commits from a release, so a feature PR aimed there cannot
> be merged.

Branch from `develop`:

```bash
git switch develop && git pull
git switch -c feature/short-description
```

Before pushing:

```bash
make format    # Prettier for YAML/Markdown/JSON, Ruff for the entrypoint
make lint      # yamllint, Ruff, Robocop, hadolint, lockfile check
make build     # VARIANT=base|browser|selenium
make test
```

Both engines are supported and both are tested in CI, so `make build ENGINE=podman`
is a fair thing to check if you are touching the Dockerfile.

## How the repository fits together

| Path                                | What it is                                                                                                    |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `Dockerfile`                        | Every variant. `common` → `builder-common` → `venv-*` → `base`/`browser`/`selenium`, selected with `--target` |
| `Containerfile`, `.containerignore` | Symlinks to the Docker-named files, so Podman finds them by its preferred names                               |
| `pyproject.toml`, `uv.lock`         | One dependency group per variant, resolved into a single hash-pinned lockfile                                 |
| `src/entrypoint/rf-entrypoint`      | Python. Handles the arbitrary-UID setup, reports directory, option parsing and rerun loop                     |
| `tests/`                            | Real suites run against every built image in CI, plus the static site they exercise                           |
| `compose.yaml`                      | One-shot runs with either engine; starts the site the browser suite needs                                     |

### Adding or changing a dependency

Edit the right group in `pyproject.toml`, then:

```bash
make lock
```

Commit both files. Never hand-edit `uv.lock`. Put a library in `base` only if
every variant genuinely needs it — that group is in all three images.

### Changing the entrypoint

It is plain Python with no third-party imports, and it runs before the
virtualenv is necessarily usable, so keep it dependency-free. If you add a
behaviour, add a case to `tests/` or a regression step to the workflow. Several
existing steps exist because a specific upstream bug report is referenced in the
code right next to them.

## Design decisions to know before changing them

These look like nits until you change one and something breaks. Each exists
because of a concrete failure, usually one visible in the predecessor project's
issue tracker.

- **The image never chowns a directory you mounted.**
  ([#403](https://github.com/ppodgorsek/docker-robot-framework/issues/403))
  The host opts in with group `0` and group-write. The entrypoint only relaxes
  permissions on directories it created itself.
- **uid `1000`, gid `0`, with a real passwd entry and a writable `$HOME`.**
  ([#425](https://github.com/ppodgorsek/docker-robot-framework/issues/425),
  [#424](https://github.com/ppodgorsek/docker-robot-framework/issues/424))
  Any uid must keep working. Do not assume uid 1000 anywhere.
- **`ROBOT_OPTIONS` is parsed with `shlex`, never handed to a shell.**
  ([#194](https://github.com/ppodgorsek/docker-robot-framework/issues/194))
  Word-splitting quoted values is the bug, not the feature.
- **A real `ENTRYPOINT` that sets up and then `exec`s.**
  ([#489](https://github.com/ppodgorsek/docker-robot-framework/issues/489))
  A caller-supplied command must still get a prepared container.
- **No `--shm-size=1g`, anywhere.** If a change makes the suites need it, that
  is the bug. Nothing in CI passes that flag.
- **No pinned `apt-get install` versions.** See `.hadolint.yaml` for why; the
  short version is that pinning against a live suite breaks builds later.
- **Full version tags are immutable.** `1.0.0-browser` is never re-pushed.
- **Size is a feature.** CI reports each image's size. If a change adds a lot,
  say so in the pull request and why it is worth it. Dropping DataDriver's
  `[xls]` extra saved 137 MB of `pandas` and `numpy`; that kind of trade is
  normal here.

## Releasing

1. Open a pull request from `develop` into `main`. Use a **merge commit**, not a
   squash — Release Please reads the individual commits to work out the version,
   and squashing hides them.
2. Release Please opens a `chore(release): x.y.z` pull request against `main`
   with the version bump and the generated `CHANGELOG.md` entry.
3. Merge it. That tags `vx.y.z`, creates the GitHub release, and publishes the
   images.

Nothing is published from `main` or `develop` directly — only from a release.
`CHANGELOG.md`, the version in `pyproject.toml` and
`.release-please-manifest.json` are all maintained by the tool; do not edit them
by hand.

## Pull requests

- One logical change per pull request.
- Title must be a Conventional Commit. Feature PRs are squash-merged, so the
  title is the commit message that ends up on `develop`.
- Explain _why_ in the description. If you measured something, include the
  numbers — the commit history is full of them and it is genuinely useful later.
- CI must be green: lint, both variants on `amd64` and `arm64`, the Podman job,
  and the Trivy gate on fixable `CRITICAL`/`HIGH`.
- If a scanner finding is genuinely not actionable, write down why rather than
  suppressing it quietly.

Dependency bumps are handled by Renovate. Patch and minor updates merge
themselves once CI passes; majors wait for a human.

## Reporting a bug

Include the image tag or digest, the architecture, your engine and version, and
the command you ran. For a browser problem, whether it reproduces with
`--only-shell` is useful to know.

Security issues go through [SECURITY.md](SECURITY.md) instead — please do not
open a public issue for those.
