# atom-frontend

Conventions for React SPAs built on the private **`@hwndmaster/atom-*`** packages.

## Skills

| Skill | Triggers on |
|-------|-------------|
| `web-frontend` | Creating, editing, building, linting or testing anything under the app's `*.Web/` folder — components, pages, store slices, sagas, forms, API integration or styles. |

## What it covers

- **pnpm policy** and the `packageManager` pin, plus the command set (`start`, `start:aspire`,
  `build`, `lint`, `test`, `test:coverage`, `nswag`) and the lint-and-test-before-done rule.
- **`src/` layout** — what `api/`, `store/`, `components/`, `pages/`, `models/`, `schemas/`,
  `shared/`, `styles/`, `telemetry/` and the `primereact.ts` barrel each hold.
- **Routing on `react-router` v8** — `createBrowserRouter` from `react-router`, `RouterProvider` from
  `react-router/dom`. Explicitly *not* `react-router-dom`.
- **The store slice pattern** — the fixed nine-file set every slice follows, the three action-creator
  flavours, and the three saga wrappers.
- **Server validation errors** end to end: validatable action → `withValidatableCallback` with the
  domain's `mapValidationField` → `translateErrorsToForm(form)` in a dumb form component.
- **Architectural boundaries** enforced by ESLint `import-x/no-restricted-paths` — UI never reaches
  into `api/` or `actionsInternal`.
- **Testing** — Vitest setup, `SagaRunner`, `fakeAxios` (including the route-parameter gotcha and the
  `showLoader` typecheck trap), `data-test_id` selection, model factories, and the explicit
  instruction not to write exhaustive suites.
- **Code conventions** — 4-space double-quoted style, zod v4, the seven-group import order, SCSS
  modules, and the naming rules from `@hwndmaster/atom-eslint-stylistic`.
- **The atom-web package policy** — ask before changing a `@hwndmaster/*` package, then ask for a publish.

## Applicability

Any app whose `*.Web/package.json` depends on `@hwndmaster/atom-react-redux`. The skill names no
specific app — it reads the web folder name, ports, store slice inventory and per-app libraries from
the consuming repo's `CLAUDE.md`.

## Install

```
/plugin install atom-frontend@geni-ai-sdlc-marketplace
```
