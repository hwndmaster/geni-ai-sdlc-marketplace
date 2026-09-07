# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repo is

A Claude Code **plugin marketplace** for the Genius/Atom application stack. It has no runtime of its
own. Work happens inside `plugins/<name>/`; the marketplace only lists them in
`.claude-plugin/marketplace.json`.

Consumers are the app repos built on the stack — currently `buddy-kenteken`, `price-checker` and
`prepper-box`. `atom` (the .NET framework) and `atom-web` (the `@hwndmaster/atom-*` packages) are
upstream of those apps and are not consumers.

## The core rule: what belongs where

Everything here exists to stop the same guidance being copy-pasted into three repos and drifting.
Three homes, and a fact lives in exactly one of them:

| Home | Holds | Example |
|------|-------|---------|
| A plugin **skill** | what is true for *every* app on the stack | "repository tests derive from Atom's `BaseRepositoryTests`" |
| A plugin **template** (`atom-devops`) | a file every app repo needs, byte-for-byte modulo name tokens | `publish-docker.ps1` |
| The consuming repo's **CLAUDE.md** | what is true for *that app only* | "the web dev server runs on 5091" |

Concretely:

- **A skill may not *depend* on an app.** No behaviour keyed to `BuddyKenteken` or `PrepperBox`, no
  hardcoded port numbers, no domain slice inventories. If you catch yourself writing one, it belongs
  in that repo's `CLAUDE.md`.
  The one carve-out is naming a real app as an **illustrative example**, where the example is itself
  the point — `sync-toolchain` cites all three service prefixes precisely to show they follow no rule
  and must be read from `docker-compose.yml`. A made-up name would not make that case. Keep such
  mentions in an "Example" column or an explicit aside, never in an instruction.
- **A managed toolchain file is edited in the template, never in a consuming repo.** If a repo's copy
  is intentionally ahead, port the change back into the template and bump the version. Do not leave a
  repo diverged — the next `sync-toolchain` run will show it as drift forever.
- **Before changing a skill, verify the claim against at least two of the three consumer repos.**
  The six skills this marketplace replaced had drifted precisely because nobody did this: two of them
  still described `react-router-dom` v7 long after all three apps moved to `react-router` v8.

## Conventions

- **Naming.** Plugins drop any prefix — the marketplace is the namespace. Skill folder names are the
  invocation names (`atom-backend:dotnet-tests`).
- **Skill triggering.** Skills activate from natural-language phrases in the `description`
  frontmatter, not from slash commands. Write the description as the things a user actually says.
- **Paths.** Never commit an absolute local dev path into a skill or template. The one exception is
  the Atom checkout probe (`C:\Dev\Src\atom`), which is genuinely part of how the stack builds and is
  documented as such.
- **Templates are inert.** Files under `skills/*/references/templates/` are data, not scripts to run
  from here. They are rendered into a consuming repo by `sync-toolchain`.

## Versioning

Bump **both** `plugins/<name>/.claude-plugin/plugin.json` and the matching `plugins[].version` in
`.claude-plugin/marketplace.json`. A stale `version` pins users to a cached copy, so a change that
ships without a bump does not reach anyone.

**Patch-bump only.** Never raise the major or minor part (`0.1.x -> 0.2.0`, `0.x -> 1.0.0`) unless
explicitly asked for that specific bump. Any number of fixes, template corrections or doc edits stays
on the same minor line.

## Validation

```
claude plugin validate .
```

Checks JSON syntax, duplicate plugin names, source path traversal, per-plugin `plugin.json`, and
version mismatches between a marketplace entry and its plugin manifest. Run it from an interactive
terminal — the `claude` CLI is not on PATH in every environment.
