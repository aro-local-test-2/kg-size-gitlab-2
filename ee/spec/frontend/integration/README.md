# Frontend integration tests

This is GitLab's frontend integration test layer. These specs mount a real
Vue app with `fullMount` and the real `apolloProvider`, then intercept
GraphQL and REST at the network layer with Mock Service Worker (MSW). That
lets a test exercise multiple components together on a page, the way a user
actually sees them, without a running backend.

This suite is EE-only. The harness and fixtures it depends on do not exist
in FOSS, and the CE path (`spec/frontend/integration/`) is blocked by an
ESLint rule. MSW mocks the network layer, including auth and licensing, so
these tests cannot assert FOSS-versus-licensed differences. Use a Capybara
feature spec for that.

## When to write one here

Write a spec in this directory when the behavior spans multiple components
on a single page and the backend responses it depends on can be represented
with generated fixtures.

Don't write one here when you need:

- Real database state.
- Authorization checks or server-side validations.
- Navigation across server-rendered pages.
- FOSS-versus-licensed differences.

Those belong in a Capybara feature spec. A single component in isolation
belongs in a plain unit test under `ee/spec/frontend/`.

## Running

```shell
yarn jest:integration
```

For a single file:

```shell
yarn jest:integration <path>
```

This suite has its own Jest config, `jest.config.integration.js`, and does
not run under the default `yarn jest`. In CI it runs in the
`jest-integration` job.

## Layout

- `core/` - fixture utilities, the variant registry, request-capture helpers.
- `helpers/` - mount and DOM helpers, including `setup_utils.js`.
- `handlers.js`, `server.js`, `polyfills.js`, `test_setup.js` - shared setup at the root.
- One directory per feature area: `work_items/`, `ai_duo_panel/` (see its own README), `ai_catalog/`, `cd/`.

## Fixtures

Fixtures are generated, never hand-written. GraphQL responses come from
running the real queries against the real API in RSpec generators under
`ee/spec/frontend/fixtures/` (for example `work_items_integration.rb`,
`ai_duo_panel_integration.rb`). They land in
`tmp/tests/frontend/fixtures-ee/` and are not committed to Git.

A hand-written mock drifts from the real schema silently. A generated one
breaks loudly when the schema changes. That loud failure is the main reason
this suite exists.

## Varying a response shape

Don't edit a handler to make an operation return a different shape.
Declare a named fixture variant instead, with `defineFixtureVariants` in
`<feature>/fixture_variants/<query>.js`. Every variant file needs a `BASE`
key. Activate a variant per test with `setQueryVariant`, imported from
`ee_jest/integration/helpers/setup_utils`. Variants reset to `BASE`
automatically after each test.

To see every registered query and its variant keys, run:

```shell
yarn integration:variants
```

This writes a manifest to
`tmp/tests/frontend/integration_variants.manifest.json`. It's regenerated on
demand and not committed.

## Troubleshooting stale fixtures

Stale fixtures are the most common cause of failures, especially after a
branch switch, rebase, or pull. Refresh them before debugging your code:

```shell
scripts/frontend/download_fixtures.sh
```

Classic symptoms of a stale or missing fixture:

- `TypeError: Cannot read properties of null (reading 'querySelectorAll')`
- `expect.hasAssertions()` receiving none
- An error alert such as "Something went wrong when fetching..."

## Full documentation

See the "Frontend integration tests" section of
[`doc/development/testing_guide/frontend_testing.md`](../../../../doc/development/testing_guide/frontend_testing.md)
for the complete guide.
