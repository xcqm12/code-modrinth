# @Bbsmc/api-client

Platform-agnostic API client for Bbsmc's services. Works in Nuxt (SSR + CSR), Tauri (desktop app), and plain Node/browser environments.

## Architecture

```
Request Flow:
  Module Method â†?client.request() â†?Feature Chain (middleware) â†?Platform executeRequest()
```

### Key Directories

- **`src/core/`** â€?base classes (`AbstractBbsmcClient`, `AbstractModule`, `AbstractFeature`, etc.)
- **`src/platform/`** â€?platform implementations (generic, nuxt, tauri, xhr-upload, websocket)
- **`src/features/`** â€?middleware plugins (auth, retry, circuit-breaker, etc.)
- **`src/modules/`** â€?API endpoint modules organized by service (`labrinth/`, `archon/`, `kyros/`, `iso3166/`)
- **`src/types/`** â€?core type definitions (client config, request options, upload types, errors)

### Client Hierarchy

All platform clients extend `XHRUploadClient` â†?`AbstractBbsmcClient`:

- **`GenericBbsmcClient`** â€?uses `ofetch`, attaches WebSocket client to `archon.sockets`
- **`NuxtBbsmcClient`** â€?uses Nuxt's `$fetch`, SSR-aware, blocks `upload()` during SSR
- **`TauriBbsmcClient`** â€?uses `@tauri-apps/plugin-http`

### Module Access

Modules are lazy-loaded and accessed as a nested structure:

```ts
client.labrinth.projects_v2
client.labrinth.projects_v3
client.labrinth.versions_v3
client.labrinth.collections
client.labrinth.billing_internal
client.archon.servers_v0
client.archon.servers_v1
client.archon.backups_queue_v1
client.archon.backups_v1
client.archon.content_v0
client.kyros.files_v0
client.iso3166.data
... etc.
```

This structure is derived at runtime from the flat `MODULE_REGISTRY` in `modules/index.ts` via `buildModuleStructure()`, and the TypeScript types are inferred automatically via `InferredClientModules`.

## Critical: Always use `this.client.request()`

API modules **must** use `this.client.request()` (or `.upload`) for all HTTP calls â€?never `$fetch`, `fetch`, or any other HTTP library directly. The request method routes through the platform-specific implementation (Nuxt `$fetch`, Tauri HTTP plugin, etc.) and the feature middleware chain (auth, retry, circuit breaker). Using `$fetch` directly bypasses the platform layer and will fail in Tauri (CORS/sandboxing). The only exception is the `ISO3166Module` which is explicitly node-only.

For external APIs (non-Bbsmc), pass the full base URL as the `api` field and set `skipAuth: true`:

```ts
this.client.request<MyType>('/endpoint', {
	api: 'https://external-api.com',
	version: 1,
	method: 'POST',
	body: { data },
	skipAuth: true,
})
```

## Usage

The client is provided to the component tree via DI (see the `dependency-injection` skill). Each app creates a platform-specific client and provides it at the root:

```ts
// apps/frontend/src/app.vue (Nuxt)
const client = new NuxtBbsmcClient({ ... })
provideBbsmcClient(client)

// apps/app-frontend/src/App.vue (Tauri)
const client = new TauriBbsmcClient({ ... })
provideBbsmcClient(client)
```

Components anywhere in the tree then inject it:

```ts
const { labrinth, archon, kyros } = injectBbsmcClient()

// Fetch data
const project = await labrinth.projects_v3.get(projectId)

// Use with TanStack Query
const { data } = useQuery({
	queryKey: ['project', projectId],
	queryFn: () => labrinth.projects_v3.get(projectId),
})
```

`provideBbsmcClient` and `injectBbsmcClient` are exported from `@Bbsmc/ui` (defined in `packages/ui/src/providers/api-client.ts`). The provider is typed as `AbstractBbsmcClient`, so shared components in `packages/ui` work with any platform client.

## Types

Types must match 1:1 with how they are returned from the backend API they are fetching from. Do not reshape, rename, or omit fields â€?the types should be a direct representation of the API response.

Types are organized in namespaces that mirror the backend services:

```ts
import type { Labrinth, Archon, Kyros, ISO3166 } from '@Bbsmc/api-client'

const project: Labrinth.Projects.v3.Project = ...
const server: Archon.Servers.v0.Server = ...
const auth: Archon.Websocket.v0.WSAuth = ...
```

Each API has a `types.ts` in its module directory (`modules/labrinth/types.ts`, `modules/archon/types.ts`, etc.) using nested namespaces: `Namespace.Domain.Version.Type`.

## Features (Middleware)

Features wrap requests in a chain. Each feature can modify the request, retry, or short-circuit:

- **`AuthFeature`** â€?injects `Authorization: Bearer <token>`, supports async token providers
- **`RetryFeature`** â€?exponential/linear/constant backoff, retries on 408/429/5xx and network errors
- **`CircuitBreakerFeature`** â€?opens after N consecutive failures per endpoint, resets after timeout

## XHR Upload

File uploads use `XMLHttpRequest` for progress tracking (not available via `fetch`). The `upload()` method returns an `UploadHandle<T>`:

```ts
interface UploadHandle<T> {
	promise: Promise<T>
	onProgress(callback: (progress: UploadProgress) => void): UploadHandle<T> // chainable
	cancel(): void
}
```

Supports two modes:

- **Single file** â€?`{ file: File | Blob }` sends with `Content-Type: application/octet-stream`
- **FormData** â€?`{ formData: FormData }` for multipart uploads (browser/platform sets boundary)

Uploads go through the feature chain (auth, retry, etc.). Features detect uploads via `context.metadata.isUpload`.

### Usage Example (server file upload)

```ts
const uploader = client.kyros.files_v0.uploadFile(path, file, {
	onProgress: ({ progress }) => {
		uploadProgress.value = Math.round(progress * 100)
	},
})
// Cancel if needed: uploader.cancel()
await uploader.promise
```

### Usage Example (version creation with FormData)

```ts
const handle = client.labrinth.versions_v3.createVersion(draftVersion, files, projectType)
handle.onProgress((progress) => {
	uploadProgress.value = progress
})
await handle.promise
```

See `packages/ui/src/components/servers/files/upload/FileUploadDropdown.vue` and `apps/frontend/src/providers/version/manage-version-modal.ts` for real usage.

## WebSocket

WebSocket support is attached to `client.archon.sockets` (only on `GenericBbsmcClient`). It provides event-based communication with Bbsmc Hosting servers.

### Connection Flow

```
client.archon.sockets.safeConnect(serverId)
  â†?fetches JWT auth via archon.servers_v0.getWebSocketAuth()
  â†?opens wss:// connection
  â†?sends { event: 'auth', jwt: token }
  â†?server responds with { event: 'auth-ok' }
  â†?ready to receive events
```

Auto-reconnects on unexpected disconnection with exponential backoff (base 1s, max 30s, up to 10 attempts).

### Subscribing to Events

```ts
const unsub = client.archon.sockets.on(serverId, 'stats', (data) => {
	// data is typed as Archon.Websocket.v0.WSStatsEvent
	cpuUsage.value = data.cpu_percent
})

// Clean up
onUnmounted(() => {
	unsub()
	client.archon.sockets.disconnect(serverId)
})
```

Event types: `log`, `stats`, `power-state`, `uptime`, `backup-progress`, `installation-result`, `filesystem-ops`, `new-mod`, `auth-expiring`, `auth-incorrect`, `auth-ok`.

### Sending Commands

```ts
client.archon.sockets.send(serverId, { event: 'command', cmd: '/say hello' })
```

See `apps/frontend/src/pages/hosting/manage/[id].vue` for the full server panel WebSocket usage.

## Adding a New API Module

See the `api-module` skill (`.claude/skills/api-module/SKILL.md`) for step-by-step instructions.
