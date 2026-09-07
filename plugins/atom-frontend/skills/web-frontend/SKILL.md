---
name: web-frontend
description: Conventions and commands for a React SPA built on the private @hwndmaster/atom-* packages — React 19 + TypeScript, Redux Toolkit + redux-saga slices, PrimeReact, Vite, Vitest with SagaRunner and fakeAxios, NSwag-generated API clients, and ESLint import boundaries. Use whenever creating, editing, building, linting or testing anything under the app's *.Web/ folder — components, pages, store slices, sagas, forms, API integration or styles.
---

# Atom web frontend

Applies to any app whose `*.Web/package.json` depends on `@hwndmaster/atom-react-redux`. React 19 +
TypeScript SPA, state via Redux Toolkit + redux-saga (+ redux-persist), UI with PrimeReact, bundled
by Vite, tested with Vitest. Shared building blocks come from the private `@hwndmaster/atom-*`
packages.

**Read the repo's `CLAUDE.md` first** for the app-specific map: the web folder name, the dev-server
and API ports, the store slice inventory, and any per-app libraries. Without one, derive what you can
from `*.Web/package.json` and `src/store/`.

## Package manager

**`pnpm`**, pinned via the `packageManager` field in `*.Web/package.json`. CI reads that field, so
bump it there and nothing drifts. Never use `npm` or `yarn`. All commands below run from the web
folder, not the repo root.

## Commands

| Task | Command |
|------|---------|
| Install deps | `pnpm install` |
| Dev server | `pnpm start` (port and `--open` are in the `start` script) |
| Dev server (Aspire) | `pnpm start:aspire` (no port flag — Aspire assigns it) |
| Build | `pnpm build` |
| Lint | `pnpm lint` (eslint, cached) |
| Test | `pnpm test` |
| Test + coverage | `pnpm test:coverage` → `coverage/lcov.info` |
| Regenerate API client | `pnpm nswag` |

After any change, run **`pnpm lint`** and **`pnpm test`** before considering it done. The build also
typechecks.

`pnpm nswag` needs the WebApi running — it reads the OpenAPI document over HTTP, so start the API
first (`dotnet run --project <Solution>.WebApi`). Coverage uses the `v8` provider and emits `text` +
`lcov`; `*.test.ts(x)` and `src/**/tests/**` are excluded from the measured sources.

## Project layout (`src/`)

- **`api/`** — the generated HTTP client. `api.generated.ts` is produced by **NSwag from the WebApi**
  (config in `nswag/webapi.nswag`) — never hand-edit it, run `pnpm nswag`. `apiAxios.ts` wires the
  singleton axios client and `setup.ts` configures it. `converters/` convert between API DTOs and app
  models, one file per domain. `fieldMapping/` maps backend (C# PascalCase) field names onto app DTO
  field names when processing server validation errors.
- **`store/`** — one folder per domain slice. `setup.ts` builds the store via `createAppStore` from
  `@hwndmaster/atom-react-redux` with **redux-persist**; bump `persistVersion` whenever the shape of
  persisted state changes, and use `persistBlacklist` for slices that are transient rather than
  persisting them. `setupSagas.ts` registers sagas, `appState.ts` is the root state, `utils.ts` holds
  `typedSelect`. `index.ts` re-exports each slice as a namespace (`store.Products.Actions`,
  `store.Scans.Selectors`) — UI code does `import * as store from "@/store"` and goes through those.
- **`components/`** — reusable UI. Forms use `react-hook-form` + zod schemas via `@hookform/resolvers`.
- **`pages/`** — route-level screens.
- **`models/`** — app-side types per domain, plus `types.ts` (entity-reference factories) and `enums.ts`.
- **`schemas/`** — zod form-validation schemas, one per entity (`<entity>Schema.ts` exporting
  `<Entity>SchemaData`).
- **`shared/`** — `constants.ts`, `routes.ts`, `loadingTargets.ts`, formatters and domain helpers.
- **`styles/`** — global SCSS (`main.scss`, `_variables.scss`, `_mixins.scss`, …). Variables and mixins
  are auto-injected into every SCSS module by `vite.config.ts`, so do not re-import them.
- **`telemetry/`** — OpenTelemetry setup (`setupOpenTelemetry.ts`), called once from `index.tsx`.
- **`utils/`** — general utilities; `utils/tests/` holds shared test fakes in some repos.
- **`primereact.ts`** — a barrel re-exporting every PrimeReact component in use. Import PrimeReact
  components from here, not from `primereact/*` directly.

## Routing

`react-router` **v8**, wired in `RootComponent.tsx`:

```tsx
import { createBrowserRouter } from "react-router";
import { RouterProvider } from "react-router/dom";
```

Note the split: the router factory comes from `react-router`, the provider from `react-router/dom`.
**Not `react-router-dom`** — that package is the v7 shape and is not what these apps use. Paths come
from `shared/routes.ts`.

## Entity references

Backend ids are wrapped rather than passed as primitives. `models/types.ts` declares them via
`EntityGuidId<"Agent">` (or the integer equivalent) and `createGuidRefConverter` from
`@hwndmaster/atom-web-core`, exporting a factory per domain — `productRef(id)`, and
`productRef.default()` for "new entity". Use the factories in app code **and** in tests instead of
raw strings or numbers.

## Store slice pattern

Each slice folder has a fixed file set. Follow it exactly when adding a slice:

- `state.ts` — the slice's state interface.
- `actions.ts` — **public** actions, the only ones other modules dispatch.
- `actionsInternal.ts` — **internal** actions, dispatched only by sagas and reducers within the slice.
- `reducers.ts` — `createReducer` over `actionsInternal`. A reducer may also react to another slice's
  *public* actions.
- `sagas.ts` — `function*` sagas using `redux-saga/effects` and `callApi` from
  `@hwndmaster/atom-react-redux`; call the API via `apiClient().<client>.<method>()` and pass the
  converters from `api/converters` to `fetch` / `fetchArray`.
- `selectors.ts` — selectors over the slice state. In sagas, read through `typedSelect`.
- `messages.ts` — the slice's non-store API surface. Present only where needed: a SignalR hub
  connection that dispatches store actions from its callbacks, a plain fetch for static data, or just
  re-exports from `api/`.
- `index.ts` — re-exports `* as Actions` and `type * as State`.
- `*.test.ts` — reducer and saga tests, colocated.

## Action creators

- `createAction` from `@reduxjs/toolkit` for simple cases.
- `createActionWithMeta` from `@hwndmaster/atom-react-redux` when the caller must handle the result —
  an error toast on rejection, a redirect on success.
- `createActionWithMetaValidatable` when the saga result may carry a validation result (form
  submissions).

## Saga wrappers

- `withLoading` — block a part of the UI, identified by a `LoadingTargets` entry from
  `shared/loadingTargets.ts`: `yield* withLoading(LoadingTargets.Products, function* () { … })`.
  It accepts an optional third argument (`param?: LoadingParam`) that scopes the loader to a single
  entity rather than the whole target. The capability is real but **no app currently uses it** — do
  not go looking for an existing example.
- `withCallback` — handle actions created with `createActionWithMeta`.
- `withValidatableCallback` — handle actions created with `createActionWithMetaValidatable`, passing
  the slice's `mapValidationField`.

## Server validation errors

Field-level errors from the server land on the matching form fields end to end:

1. the create/update **action** is `createActionWithMetaValidatable<Req, Ref, XSchemaData>`;
2. the **saga** wraps its work in `withValidatableCallback(meta, { mapValidationField }, …)` using the
   domain's mapper from `api/fieldMapping/`, which maps C# PascalCase names onto zod schema field names;
3. the **form** passes `translateErrorsToForm(form)` on submit.

Forms are "dumb" — the parent page dispatches the action — so they forward the translator through
their `onSubmit` / `onSave` callback. A form that dispatches directly passes it inline.

## Architectural boundaries

Enforced by ESLint `import-x/no-restricted-paths`. These are hard rules — violating them fails lint:

- `api/` may **only** be imported from `store/`.
- Within a slice, only `sagas.ts`, `messages.ts` and `apiRequest.ts` may import from `api/`.
  Saga *tests* are exempted by an explicit override, as are shared test fakes.
- `actionsInternal.ts` may only be imported within `store/`.
- `sagas.ts` may only be imported within `store/`.

So UI (`components/`, `pages/`) dispatches **public** actions and reads state through selectors and
hooks. It never touches `api/` or `actionsInternal` directly.

## Testing conventions

- Vitest with `globals: true` (no need to import `describe` / `it` / `expect`), `jsdom` environment,
  `setupTests.ts` setup file. `@hwndmaster/atom-*` packages are inlined via `server.deps.inline` in
  `vitest.config.ts` — add new ones there.
- Tests are colocated as `*.test.ts(x)` next to their target file.
- Use the `@/` path alias for `src/` imports.
- Follow the **Arrange / Act / Assert** comment structure.
- **ALWAYS select screen elements by their `data-test_id` attribute.** If an element does not have
  one, add it to the component. Format `ComponentName__Element_Description`, e.g.
  `ProductEdit__Save_Button`. Do not select by visible text.
- Build test data with the model factories (`utils/tests/testModels.ts` or the reference factories in
  `models/types.ts`) plus `Partial<T>` overrides, rather than hand-building objects. Extend the factory
  file when a new domain model needs one.
- When testing a specific function (reducer, action, helper), name the test
  `functionName: description of the test case`.
- **Do not write exhaustive suites.** Cover rendering, the main logic, the standard business scenarios
  and the most likely edge cases.

### Saga tests

Each slice has a colocated `sagas.test.ts`:

- Drive the saga with `SagaRunner` from `@hwndmaster/atom-testing-utils`, typed as
  `new SagaRunner<AppState>()`, and run it with `await sagaRunner.runSaga(mySaga, action)`.
- Mock HTTP with the repo's shared `fakeAxios` — it lives at either `@/store/testUtils/sagas` or
  `@/utils/tests/fakeAxios`; check which. Set expectations with
  `fakeAxios.setupGet(api.CategoriesClient, "categoriesAll").reply(200, [dto])`, plus `setupPost` /
  `setupPut` / `setupDelete`. The operation name is the generated client method, and **route
  parameters must be supplied** (`setupDelete(api.CategoriesClient, "categoriesDELETE", { id: categoryRef(4) })`)
  or the URL will not match. Passing `{ body: request }` additionally asserts the request payload.
- **Reset both in `beforeEach`**: `fakeAxios.reset()` and `sagaRunner.reset()`, plus
  `vi.clearAllMocks()`. `reset()` does *not* clear the initial state, so re-seed it with
  `sagaRunner.setInitialState(...)` — only the slices the saga actually selects from.
- Assert store updates with `sagaRunner.findDispatchedAction(actionsInternal.setCategory)`, which
  returns the payload.
- Assert `withLoading` with
  `expect(sagaRunner.dispatched).toContainEqual({ type: Common.Actions.showLoader.type, payload: LoadingTargets.Categories })`.
  Do **not** pass `Common.Actions.showLoader` to `findDispatchedAction` — its prepared payload type
  does not match and the test fails to typecheck.
- Cover `withCallback` / `withValidatableCallback` outcomes by passing the meta callbacks straight into
  the action creator and spying on them: `actions.createCategory(request, validationReject, resolve, reject)`.
  Use `vi.fn<(reason?: string) => void>()` so the mock stays typed.

## Code conventions

- Indentation **4 spaces**; **double-quoted** strings.
- Prefer PrimeReact components (through the `src/primereact.ts` barrel) and the
  `@hwndmaster/atom-react-*` helpers over hand-rolling.
- Validation schemas use **zod v4** under `schemas/`, wired to forms via `react-hook-form` +
  `@hookform/resolvers`.
- Avoid `as unknown as Type` / `as unknown as never` unless genuinely unavoidable — restructure the
  types instead.
- **Import order** in a React component file:
  1. React and related libraries
  2. Third-party libraries
  3. `@hwndmaster/atom-*` packages
  4. Application-wide imports, in this order:
     - store (`import * as store from "@/store";`)
     - API (`import * as api from "@/api/api.generated";`)
     - models (`import ProductOverview from "@/models/productOverview";`)
     - utilities (`import { formatPrice } from "@/shared/formatters";`)
     - components (`import ProductEdit from "@/components/productEdit/productEdit";`)
  5. Components from an upper folder (`import AnotherComponent from "../anotherComponent";`)
  6. Local imports (`import AnotherComponent from "./anotherComponent";`)
  7. Styles (`import "./myComponent.module.scss";`)

## CSS

- Always SCSS Modules or `main.scss`; stack styles in layers (component / feature / global).
- camelCase class names, accessed as `styles.myClassName` — never bracket notation.

## Naming

PascalCase for type names and constants (`const MaxUsers = 100;`), camelCase for variables and
functions — per the `@typescript-eslint/naming-convention` rules shipped in
`@hwndmaster/atom-eslint-stylistic` and pulled in by `eslint.config.js`.

## atom-web packages

Packages under the `@hwndmaster` scope are the atom-web packages, developed in the `atom-web` repo.

If a change there is needed: **ask first**, then make it. Afterwards ask for the new versions to be
published and continue. If publishing is deferred, assume the published versions will contain the
change and proceed without waiting.
