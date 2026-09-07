# atom-devops

The build, publish and CI plumbing every Genius/Atom app repo shares — kept as versioned templates
instead of copies.

## Skills

| Skill | Triggers on |
|-------|-------------|
| `sync-toolchain` | "sync the toolchain", "update the build scripts", "is my CI up to date", "compare this repo against the templates", bootstrapping a new app repo. |
| `docker-publish` | "publish the docker images", "push to ghcr", "clean up old package versions", or either script failing on tokens, scopes or an unreachable Docker daemon. |

## Why this exists

The eight files below were duplicated across three app repos and differed only in name tokens:

| File | State before |
|------|--------------|
| `scripts/docker-dotnet-restore.sh` | byte-identical in all three |
| `.config/dotnet-tools.json` | byte-identical in all three |
| `nuget.config` | identical content; one repo had LF where the others had CRLF |
| `publish-docker.bat` | identical; one repo was missing the trailing newline |
| `.github/workflows/ci.yml` | 111 lines, differing only in the solution name |
| `publish-docker.ps1` | 171 lines, differing only in image and service names |
| `packages-cleanup.ps1` | 207 lines, differing only in the prune list |
| `CodeCoverage.runsettings` | exclusions mechanically derived from the test projects |

Keeping three copies meant fixes landed in one repo and not the others. The clearest example: only
one of the three listed `-apphost` in its prune list, so the other two had been accumulating
undeleted apphost package versions in ghcr.io indefinitely. The template carries the fix for everyone.

## How it works

Templates live in `skills/sync-toolchain/references/templates/`. Three tokens are resolved from the
repo itself — no config file:

- `SolutionName` — basename of the `*.slnx`
- `ComposeProject` — the repo directory name, which Docker Compose uses to prefix built image names
- `ServicePrefix` — the common prefix of the `services:` keys in `docker-compose.yml`

`ServicePrefix` is deliberately read rather than derived: across the existing apps it is sometimes the
squashed solution name and sometimes the hyphenated directory name.

`CodeCoverage.runsettings` additionally expands one exclusion entry per test project.

`sync-toolchain` renders, diffs against the repo, and applies **only what you approve** — file by
file, with the diff shown first. It never overwrites an existing `docker-compose.yml`; ports, volumes
and per-app environment there are genuinely app-specific, so that template is for bootstrapping a new
repo only.

## Line endings

Templates preserve each file's own line endings, which are not uniform:

- **LF** — `docker-dotnet-restore.sh` (it runs in a Linux container), `ci.yml`, `CodeCoverage.runsettings`
- **CRLF** — `nuget.config`, `dotnet-tools.json`, `publish-docker.ps1`, `publish-docker.bat`, `packages-cleanup.ps1`

Rewriting them produces a whole-file diff that hides the real change, so read and write bytes. Do not
pipe a template through `sed` — it strips carriage returns.

## Install

```
/plugin install atom-devops@geni-ai-sdlc-marketplace
```
