---
name: dotnet-tests
description: Conventions and commands for the .NET test suite of a solution built on the Genius.Atom framework — xUnit v3, AutoFixture + FakeItEasy, Atom TestingUtil (FakeDateTime, FakeLogger, BaseRepositoryTests), EF Core repository tests, migrate-on-startup schema guards, and WebApplicationFactory integration tests over SQLite. Use whenever writing, editing, running or debugging tests in a *.Tests or *.IntegrationTests project, when a dotnet build or test fails on Atom package resolution, or when measuring .NET code coverage.
---

# Genius.Atom .NET tests

Applies to any solution whose `Directory.Build.props` imports `Genius.Atom.Build.props` and whose
root namespace is `Genius.<Solution>.*`.

**Read the repo's `CLAUDE.md` first.** It carries the solution map: which test projects exist, what
each covers, and the app-specific integration-test infrastructure. If there is no `CLAUDE.md`, derive
what you need from the `*.slnx` file and the `*.Tests` / `*.IntegrationTests` directories — and
mention that the repo would benefit from one.

## Commands

`<Solution>` below is the basename of the `.slnx` file. All commands run from the repo root.

| Task | Command |
|------|---------|
| Run all tests | `dotnet test <Solution>.slnx` |
| Run one project | `dotnet test <Solution>.Db.Tests` |
| Filter by name | `dotnet test --filter "FullyQualifiedName~WorkflowScenario"` |
| Build only | `dotnet build <Solution>.slnx` |
| Coverage (lcov) | `dotnet test <Solution>.slnx /p:CollectCoverage=true /p:CoverletOutputFormat=lcov /p:CoverletOutput=./coverage/` |

Coverlet is wired for every test project by `Directory.Build.props`: format `lcov`, written to each
project's own `coverage/` folder. Exclusions — migrations, the test assemblies themselves, and
`[ExcludeFromCodeCoverage]` — live in `CodeCoverage.runsettings`, referenced through
`RunSettingsFilePath`. In VS Code the `test dotnet coverage` task runs the whole solution with coverage.

## Atom build coupling — read this before diagnosing a build failure

`Directory.Build.props` resolves Atom's build assets in this order:

1. `C:\Dev\Src\atom\Atom.Build\build` if that directory exists (local development against the Atom source);
2. otherwise `$(USERPROFILE)` / `$(HOME)` + `/.nuget/packages/genius.atom.build/$(AtomPackageVersion)/build`
   (CI and Docker, using the package that `dotnet tool restore` unpacks).

Three consequences:

- **The solution builds against your local Atom checkout whenever it exists.** After changing anything
  in `atom`, build it first (`dotnet build C:\Dev\Src\atom\Atom.slnx`) or the app compiles against
  stale DLLs.
- **A running app locks those DLLs.** An Aspire AppHost or a `dotnet run` on the WebApi holds
  `<Solution>.WebApi\bin\`, and the next build fails with MSB3021 / MSB3027. Stop the app first.
- **`AtomPackageVersion` and `.config/dotnet-tools.json` must agree.** If they drift, the package
  folder does not exist, both imports silently no-op, central package management stays off, and
  restore fails with a misleading **NU1015 on the AppHost**. The `EnsureAtomBuildAssets` target exists
  to catch exactly this and says what to fix — report its message rather than chasing NU1015.

## Project wiring

Test projects pull Atom in through MSBuild flags from `Genius.Atom.Build.props`, not through
`PackageReference`. Set the ones the project needs in its `.csproj`:

```xml
<ReferenceAtomInfrastructure>true</ReferenceAtomInfrastructure>
<ReferenceAtomData>true</ReferenceAtomData>
<ReferenceAtomDataEf>true</ReferenceAtomDataEf>
<ReferenceAtomWeb>true</ReferenceAtomWeb>
```

The matching `*.TestingUtil` packages come along automatically. Only non-Atom packages are listed
explicitly (`Microsoft.AspNetCore.Mvc.Testing`, `Microsoft.EntityFrameworkCore.Sqlite`,
`Microsoft.EntityFrameworkCore.InMemory`), and always **versionless** — versions live in
`Directory.Packages.props` under central package management.

## Frameworks and idioms

- **xUnit v3.** Pass `TestContext.Current.CancellationToken` to every async repository, EF, file and
  HTTP call. Existing tests do; match them.
- **AutoFixture + FakeItEasy.** `AutoFixture.AutoFakeItEasy` is globally `using`-imported into every
  test project via `Directory.Build.props`, so no `using` line is needed. FakeItEasy for fakes
  (`A.Fake<T>()`, `A.CallTo(...)`), AutoFixture for data (`new Fixture()`,
  `_fixture.Build<T>().With(...).Create()`). Add `new OmitOnRecursionBehavior(recursionDepth: 2)`
  when building object graphs that reference back into themselves.
- **Atom TestingUtil.** `Genius.Atom.Infrastructure.TestingUtil` provides `FakeDateTime`
  (`new FakeDateTime()`, `.Advance(TimeSpan)`) for deterministic time and `FakeLogger<T>` — assert
  over `.Logs`, e.g. `Assert.DoesNotContain(_logger.Logs, x => x.LogLevel is LogLevel.Error)`.
  `Genius.Atom.Data.Ef.TestingUtil` provides `BaseRepositoryTests<...>`.
- **Assertions** use the built-in xUnit `Assert.*` API (`Assert.Equal`, `Assert.Contains`,
  `Assert.Single`, `Assert.Empty`, `Assert.Null`). No fluent assertion library.
- Test classes are `public sealed`; test methods are `[Fact]`, or `[Theory]` + `[InlineData]` for
  parameterized cases. Helper infrastructure inside a test project is `internal sealed`.
- When a test drives asynchronous code, prefer a **deterministic signal** over sleeping or polling —
  for example a logger that completes a `TaskCompletionSource` when the awaited entry arrives.

## Structure and naming

- Namespace mirrors the project: `namespace Genius.<Solution>.Db.Tests;`.
- Method names follow `MethodOrScenario_GivenSomething_WhenCondition_ThenExpectedOutcome`. **Parts are
  optional** — drop `GivenSomething` or the `When` clause when the scenario does not need it.
  `UpdateAsync_MovesStockToAnotherStorageLocation` and
  `FullCrudLifecycle_GivenAgent_WhenCreatedUpdatedAndDeleted_ThenAllStagesSucceed` are both correct.
- Bodies use **Arrange / Act / Assert** comment sections. Lifecycle tests that interleave the phases
  use `// Act & Assert: <stage>` per stage instead.
- Integration scenario tests carry a `/* Scenario Summary + numbered Steps */` block above `[Fact]`,
  with matching `// Step N:` comments inline. Preserve that style when extending them.

## Repository tests

**Default to Atom's `BaseRepositoryTests<...>`** from `Genius.Atom.Data.Ef.TestingUtil`. It supplies
the whole CRUD lifecycle including the optimistic-concurrency conflict case, so a repository test
class is usually just three overrides:

```csharp
public sealed class CategoriesRepositoryTests : BaseRepositoryTests<int, CategoryRef, CategoryDto,
    CreateCategoryRequest, UpdateCategoryRequest, ICategoriesRepository, AppDbContext>
{
    // Override: CreateRepository(IDatabaseContext), CreateSampleCreateDto(), CreateSampleUpdateDto()
}
```

For anything the base class does not cover, some repos keep a hand-rolled `RepositoryTestContext` —
an `IDatabaseContext` over the EF **in-memory** provider with a fresh `Guid` database name, bypassing
DI entirely (no SQLite, no migrations):

```csharp
await using var context = new RepositoryTestContext();
```

Check whether the repo actually has one before reaching for it. When writing such a test by hand:

- Inject fakes like `FakeDateTime` into the repository under test.
- Exercise the full CRUD lifecycle in one test and assert on `GetByIdOrThrowAsync` / `GetAllAsync`,
  including that deletion leaves the set empty.
- Requests are the positional `Dto.RequestMessages` records — keep argument order in sync with the
  record definition.
- Optimistic concurrency: `UpdateAsync` takes the previous `LastModified` token. Advance
  `FakeDateTime` before asserting the token moved, or it may not.

Anything touching the filesystem creates its directory in the constructor via
`Directory.CreateTempSubdirectory` and removes it in `Dispose`.

## Migration and schema tests

Where the app migrates on startup (Atom's `IDatabaseMigrator.MigrateWithBackupAsync`):

- Use real SQLite files under a `Directory.CreateTempSubdirectory` folder, and call
  `SqliteConnection.ClearAllPools()` before deleting them or the files stay locked.
- `InitialCreateMigration_ProducesSameSchemaAsEnsureCreated` is the **schema-drift guard**. If it
  fails after a model change, scaffold a new EF migration — never edit an existing one. The production
  database is baselined and must not re-run `InitialCreate`.
- Resolve the migrator and backup services through a minimal `ServiceCollection` rather than the app's
  full composition root.

Changing an entity or a `DbContext` mapping needs a migration:
`dotnet ef migrations add <Name> --project <Solution>.Db --startup-project <Solution>.Db`.
In-memory repository tests will not catch a missing migration; the SQLite integration tests will.

## Integration tests

Infrastructure lives in the test project's `Infrastructure/` folder and follows a fixed shape:

- **`<Solution>WebApiFactory`** — a `WebApplicationFactory<Program>` running the real `Program.cs`
  (migrations and mandatory-data seeding included) under the `IntegrationTests` environment, against a
  SQLite `:memory:` connection **held open for the lifetime of the factory** — closing it drops the
  database. The `IntegrationTests` environment is what lets the app skip sample data, disable backups,
  and park background workers outside their trigger window so they never fire mid-test.
- **`ApiScenarioClient`** — typed helpers over `HttpClient` for the CRUD controllers, plus raw
  `PostJsonAsync` / `PutJsonAsync` for negative cases, the route constants, and JSON extractors.
- **`Fake*HttpMessageHandler`** — stubs each external service so tests stay hermetic, swapped in as
  the primary handler of the typed client registered under that logical name.
- **`HttpClientJsonExtensions`** — `GetJsonAsync` returning a cloned `JsonElement`.

```csharp
using var factory = new AppWebApiFactory();
using var httpClient = factory.CreateClient();
var api = new ApiScenarioClient(httpClient);
// ... drive endpoints through `api`, assert on the returned JsonElements
```

**Reuse and extend `ApiScenarioClient` and the factory rather than calling raw endpoints inline** —
scenarios should read as numbered steps. Where a repo has no `ApiScenarioClient` yet and tests drive
`HttpClient` directly, that is fine until the same request/parse helper appears a third time; then
factor it into `Infrastructure/` instead of copying it again.

### Wire behaviour to expect

These come from Atom itself, so they hold in every app:

- **Routes are versioned.** Atom's `BaseController` carries
  `[Route("api/v{version:apiVersion}/[controller]")]`, so every controller answers on
  `/api/v1/<ControllerName>` without declaring a route of its own. CRUD controllers derive from
  `BaseCrudController<TId, TRef, TDto, TRepository, TCreateRequest, TUpdateRequest>`, which supplies
  the standard verbs — a controller only adds what is genuinely extra.
- `DateTimeOffset` serializes as **UTC ticks** (`DateTimeOffsetTicksConverter`). Entity references and
  enums serialize as **plain integers**. Note that `TId` may be `int` or `Guid` depending on the app —
  check the controller's generic arguments rather than assuming.
- The database stores timestamps as **Unix seconds**, so sub-second precision does not round-trip.
  Build expected values through the helper the test project provides rather than from a raw
  `DateTimeOffset`.
- Optimistic concurrency: every update takes the `lastModified` token from the preceding
  create/update or a GET. A stale token surfaces as **HTTP 409** with an enriched `ProblemDetails`
  (`title`, `entityType`, `entityId`) from Atom's `VersionConflictExceptionFilter`.
- MVC JSON uses `JsonUnmappedMemberHandling.Disallow`, so a request payload must carry **exactly** the
  properties of its request record — an extra member is a 400, not a silently ignored field.
- Request validators must be registered under the **non-generic** `IRequestValidator` service type.
  Registering the closed generic silently disables them, because Atom's `RequestValidators` resolves
  `IEnumerable<IRequestValidator>`. Worth a dedicated integration test guarding it.

## When adding a test

1. Pick the right project: repository or schema work goes to `*.Db.Tests`; pure domain logic to
   `*.Core.Tests`; WebApi services, validators and workers to `*.WebApi.Tests`; anything crossing HTTP
   to `*.WebApi.IntegrationTests`.
2. Match the naming, `sealed`-class, AAA and (for integration) numbered-step conventions above.
3. Run `dotnet test` for that project and confirm green before calling it done.
