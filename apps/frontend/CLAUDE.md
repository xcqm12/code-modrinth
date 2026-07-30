# apps/frontend â€?Bbsmc Website

Nuxt 3 application serving the main Bbsmc website. Uses Vue 3, Tailwind CSS v3, and file-based routing.

## Architecture

Nuxt 3 with SSR â€?pages are server-rendered and hydrated on the client. Uses `$fetch` for server-side data fetching and `@Bbsmc/api-client` (via `NuxtBbsmcClient`) for client-side API calls.

## Key Directories

- **`src/pages/`** â€?file-based routing (`[param].vue` for dynamic segments, nested folders for nested routes)
- **`src/components/`** â€?website-specific components (not shared with the app)
- **`src/composables/`** â€?Vue composables, including `queries/` for TanStack Query options
- **`src/providers/`** â€?page-level DI context providers (e.g., version modal, project page)
- **`src/plugins/`** â€?Nuxt plugins (TanStack Query setup, theme, etc.)
- **`src/middleware/`** â€?route guards and auth checks
- **`src/layouts/`** â€?Nuxt layout components
- **`src/server/`** â€?server-side plugins, routes, and utilities
- **`src/store/`** â€?Pinia state management
- **`src/helpers/`** â€?utility functions
- **`src/locales/`** â€?i18n translation files

## Components

**Website-specific components go in `src/components/`.** These are components that only make sense in the website context â€?admin panels, moderation tools, dashboard widgets, brand components, etc.

**Shared components go in `packages/ui`.** If a component could be used by both the website and the desktop app, it belongs in `packages/ui/src/components/`. See `packages/ui/CLAUDE.md` for UI standards, color rules, and component patterns.

Rule of thumb: if it doesn't depend on Nuxt-specific APIs or website-only features, it should be in `packages/ui`.

## Data Fetching

Use `@Bbsmc/api-client` via `injectBbsmcClient()` for all API calls. See `packages/api-client/CLAUDE.md` for the full API client documentation.

For caching and server state, use TanStack Query (`@tanstack/vue-query`). See the `tanstack-query` skill (`.claude/skills/tanstack-query/SKILL.md`) for patterns and conventions used in this codebase.

### Deprecated Composables

These composables are deprecated and should not be used in new code:

- **`useAsyncData`** - we use tanstack, not nuxt's built in async data utility.
- **`useBaseFetch`** (`src/composables/fetch.js`) â€?legacy Labrinth fetch wrapper. Use `client.labrinth.*` modules instead.
