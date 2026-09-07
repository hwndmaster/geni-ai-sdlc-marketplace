# atom-backend

Test conventions for .NET solutions built on the **Genius.Atom** framework.

## Skills

| Skill | Triggers on |
|-------|-------------|
| `dotnet-tests` | Writing, editing, running or debugging tests in a `*.Tests` / `*.IntegrationTests` project; a build failing on Atom package resolution; measuring .NET code coverage. |

## What it covers

- The **Atom build coupling** — how `Directory.Build.props` resolves Atom's build assets from either a
  local `atom` checkout or the restored `genius.atom.build` package, and the three failure modes that
  follow from it (stale DLLs, locked `bin\`, and the NU1015 that really means a `dotnet-tools.json`
  version drift).
- **Project wiring** through the `ReferenceAtom*` MSBuild flags rather than `PackageReference`.
- **Idioms**: xUnit v3 cancellation tokens, AutoFixture + FakeItEasy, `FakeDateTime`, `FakeLogger<T>`,
  sealed test classes, deterministic signals over sleeping.
- **Naming and structure**: the `Method_Given_When_Then` pattern, Arrange/Act/Assert sections, and the
  numbered-step block for integration scenarios.
- **Repository tests** built on Atom's `BaseRepositoryTests<...>`, with the hand-rolled
  `RepositoryTestContext` as the escape hatch.
- **Migration and schema tests**, including the `InitialCreate` schema-drift guard.
- **Integration tests**: the `WebApiFactory` + `ApiScenarioClient` + `Fake*HttpMessageHandler` shape,
  and the Atom wire behaviour to expect (UTC ticks, integer refs, 409 version conflicts,
  `JsonUnmappedMemberHandling.Disallow`, the non-generic `IRequestValidator` registration trap).

## Applicability

Any solution whose `Directory.Build.props` imports `Genius.Atom.Build.props`. The skill knows nothing
about any specific app — it reads the solution map, test-project inventory and app-specific
integration infrastructure from the consuming repo's `CLAUDE.md`, falling back to deriving what it can
from `*.slnx` and the test directories.

## Install

```
/plugin install atom-backend@geni-ai-sdlc-marketplace
```
