# geni-ai-sdlc-marketplace

A [Claude Code](https://code.claude.com/docs) plugin marketplace for the Genius/Atom application
stack — the shared conventions and build plumbing behind `buddy-kenteken`, `price-checker` and
`prepper-box`.

## Plugins

| Plugin | Skills | What it owns |
|--------|--------|--------------|
| `atom-backend` | `dotnet-tests` | Test conventions for .NET solutions on the `Genius.Atom` framework — xUnit v3, AutoFixture + FakeItEasy, Atom `TestingUtil`, EF Core repository and schema tests, `WebApplicationFactory` integration tests. |
| `atom-frontend` | `web-frontend` | Conventions for React SPAs on the `@hwndmaster/atom-*` packages — the Redux Toolkit + saga slice layout, PrimeReact, Vitest with `SagaRunner`, and the ESLint import boundaries. |
| `atom-devops` | `sync-toolchain`, `docker-publish` | The build/publish/CI files every app repo shares, as versioned templates. Renders them into a repo, reports drift, and drives the ghcr.io publish flow. |

## Adding the marketplace

From a local checkout:

```
/plugin marketplace add C:/Dev/Src/geni-ai-sdlc-marketplace
```

Once it is pushed to GitHub:

```
/plugin marketplace add hwndmaster/geni-ai-sdlc-marketplace
```

Then install what you need and reload:

```
/plugin install atom-backend@geni-ai-sdlc-marketplace
/plugin install atom-frontend@geni-ai-sdlc-marketplace
/plugin install atom-devops@geni-ai-sdlc-marketplace
/reload-plugins
```

To wire it per-repo instead of per-user, put this in the app repo's `.claude/settings.json` (it
applies once you trust the folder):

```json
{
  "extraKnownMarketplaces": {
    "geni-ai-sdlc-marketplace": {
      "source": {
        "source": "github",
        "repo": "hwndmaster/geni-ai-sdlc-marketplace"
      }
    }
  },
  "enabledPlugins": {
    "atom-backend@geni-ai-sdlc-marketplace": true,
    "atom-frontend@geni-ai-sdlc-marketplace": true,
    "atom-devops@geni-ai-sdlc-marketplace": true
  }
}
```

## The CLAUDE.md contract

The skills here deliberately know nothing about any specific app. They carry only what holds for
every app on the stack, and they read the app-specific map — solution layout, ports, store slices,
domain quirks — from the consuming repo's own `CLAUDE.md`.

That means each app repo needs a `CLAUDE.md` with at least:

- a **solution map**: the projects and what each is for, including the test projects
- **ports**: web dev server, API, and anything else bound locally
- **backend specifics**: which external services are faked in integration tests, and how
- **frontend specifics**: the store slice inventory and any per-app libraries
- the **compose service prefix**, which `atom-devops` cannot derive from the solution name

If that file is missing, the skills fall back to deriving what they can from `*.slnx`,
`*.Web/package.json` and `docker-compose.yml` — it works, but it costs a discovery pass every session.

## Layout

```
.claude-plugin/marketplace.json   # the catalog
plugins/<name>/                   # one directory per plugin
  .claude-plugin/plugin.json      # plugin manifest
  skills/<skill>/SKILL.md         # a skill
  skills/<skill>/references/      # templates and reference material
```

## Contributing

See [CLAUDE.md](CLAUDE.md) for the rules that keep this from drifting — chiefly: a skill may not name
an app, a managed file is edited in its template rather than in a consuming repo, and both version
fields get bumped together.
