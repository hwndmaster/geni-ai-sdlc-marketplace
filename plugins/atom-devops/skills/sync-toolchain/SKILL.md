---
name: sync-toolchain
description: Install or refresh the shared build, publish and CI files of a Genius/Atom app repo from versioned templates, and report drift. Use when asked to sync the toolchain, update the build scripts, check whether CI is up to date, compare a repo against the plugin templates, bootstrap the tooling for a new app repo, or when publish-docker.ps1, packages-cleanup.ps1, ci.yml, nuget.config, dotnet-tools.json or CodeCoverage.runsettings needs changing.
---

# Sync the app toolchain

Every app repo on the Genius/Atom stack carries the same build, publish and CI files. They differ only
in name tokens, so this plugin holds them as templates and each repo gets a rendered copy.

**The template is the source of truth.** A change to one of these files belongs in the template,
followed by a version bump — never in a single repo. A repo edited directly will show as drift on
every future run.

Templates live in `${CLAUDE_PLUGIN_ROOT}/skills/sync-toolchain/references/templates/`.

## Managed files

| Template | Renders to | Tokens |
|----------|-----------|--------|
| `docker-dotnet-restore.sh` | `scripts/docker-dotnet-restore.sh` | none |
| `dotnet-tools.json` | `.config/dotnet-tools.json` | none |
| `nuget.config` | `nuget.config` | none |
| `publish-docker.bat` | `publish-docker.bat` | none |
| `publish-docker.ps1` | `publish-docker.ps1` | `ServicePrefix`, `ComposeProject` |
| `packages-cleanup.ps1` | `packages-cleanup.ps1` | `ServicePrefix` |
| `ci.yml` | `.github/workflows/ci.yml` | `SolutionName` |
| `CodeCoverage.runsettings` | `CodeCoverage.runsettings` | `SolutionName`, test-project list |
| `docker-compose.yml` | `docker-compose.yml` | **new repos only** — see below |

Anything else in the repo is not managed here. In particular `.vscode/`, `Directory.Build.props`,
`Directory.Packages.props` and the `Dockerfile`s are each repo's own.

## Resolving the tokens

All three come from the repo itself. Resolve them first and state what you found before rendering
anything.

| Token | Where it comes from | Example |
|-------|--------------------|---------|
| `SolutionName` | basename of the `*.slnx` file at the repo root | `BuddyKenteken` |
| `ComposeProject` | the repo directory name — Docker Compose uses it as the project name, which is what prefixes built image names | `buddy-kenteken` |
| `ServicePrefix` | the common prefix of the `services:` keys in `docker-compose.yml` | `buddykenteken` |

**`ServicePrefix` must be read, never guessed.** It does not follow from the solution name or the
directory name — across the existing apps it is `buddykenteken`, `pricechecker` and `prepper-box`
respectively, i.e. sometimes the squashed solution name and sometimes the hyphenated directory name.
Read `docker-compose.yml`, or run `docker compose config --services`. If the repo has no
`docker-compose.yml` yet, ask rather than assuming.

The **test-project list** is the `*.Tests` and `*.IntegrationTests` directories at the repo root,
named relative to the solution (`Db.Tests`, `WebApi.Tests`, `WebApi.IntegrationTests`), in solution
layering order: `Core` → `Db` → `WebApi` → `WebApi.Integration`.

## Rendering

Substitute `{{SolutionName}}`, `{{ComposeProject}}` and `{{ServicePrefix}}` literally.

`CodeCoverage.runsettings` additionally carries two block placeholders, each on its own line, which
expand to one entry per test project at **16 spaces** of indentation:

`{{TestProjectModulePaths}}` →

```
                <ModulePath>.*\\<Solution>\.<TestProject>\.dll$</ModulePath>
```

`{{TestProjectSources}}` →

```
                <Source>.*\\<Solution>\.<TestProject>\\.*</Source>
```

with every `.` in `<Solution>` and `<TestProject>` escaped as `\.`. The `Db\Migrations` source
exclusion is already in the template and is not part of the generated block.

### Line endings

Preserve each template's own line endings exactly — they are not uniform, and rewriting them produces
a whole-file diff that hides the real change:

- **LF**: `docker-dotnet-restore.sh` (it runs inside a Linux container), `ci.yml`,
  `CodeCoverage.runsettings`
- **CRLF**: `nuget.config`, `dotnet-tools.json`, `publish-docker.ps1`, `publish-docker.bat`,
  `packages-cleanup.ps1`

Read and write bytes, or decode and re-encode without normalising. Do not pipe a template through
`sed` — it strips carriage returns.

## The sync itself

1. **Resolve the tokens** and report them.
2. **Render every managed template** to a temporary location.
3. **Compare** each rendered file against the repo's copy and classify it:
   - *identical* — nothing to do, say so in one line;
   - *missing* — the repo does not have the file at all;
   - *drifted* — show the diff.
4. **Present the summary**, then apply **only what the user approves**, file by file. Show the diff
   before asking. Never write the whole set silently.
5. For a drifted file, ask which direction is right before applying. If the repo's copy is the better
   one, the fix is to port it into the template and bump the plugin version — say so rather than
   overwriting the repo.

### `docker-compose.yml` is bootstrap-only

Never overwrite an existing `docker-compose.yml`. Ports, volume mounts and per-app environment are
genuinely app-specific — one app publishes HTTPS with mounted certs, another injects notification
credentials. Render it only when the file is absent, and then treat it as a starting point: it carries
extra tokens (`DashboardPort`, `OtlpGrpcPort`, `OtlpHttpPort`, `ApiHostPort`, `ApiContainerPort`,
`WebHostPort`, `WebContainerPort`, `DataVolumePath`, `LogsVolumePath`) that have no repo-derivable
answer, so ask for each.

## Bootstrapping a new app repo

Same flow, except everything is *missing* rather than *drifted*. Render all nine templates, ask for
the compose ports and volume paths, and afterwards remind the user that the repo still needs its own
`CLAUDE.md` — the `atom-backend` and `atom-frontend` skills read the solution map from it.
