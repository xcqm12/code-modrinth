# @Bbsmc/api-client

[![TypeScript](https://img.shields.io/badge/TypeScript-5.0+-c78aff?style=for-the-badge)](https://www.typescriptlang.org/)
[![License: LGPL-3.0](https://img.shields.io/badge/License-LGPL%203.0-c78aff?style=for-the-badge)](LICENSE)

Platform-agnostic TypeScript client for Bbsmc's API across Node.js, browsers, Nuxt, and Tauri.

**⚠️ We use this internally to power bbsmc.org.cn, Bbsmc App, and Bbsmc Hosting frontends. It may break without any notice, but you are welcome to use it.**

## Installation

```bash
pnpm add @Bbsmc/api-client
```

Tauri apps also need the optional peer dependency:

```bash
pnpm add @Bbsmc/api-client @tauri-apps/plugin-http
```

## Usage

### Generic Node.js or Browser Client

```ts
import { AuthFeature, GenericBbsmcClient, type Labrinth } from '@Bbsmc/api-client'

const client = new GenericBbsmcClient({
	userAgent: 'my-app/1.0.0',
	features: [new AuthFeature({ token: process.env.Bbsmc_TOKEN })],
})

const project: Labrinth.Projects.v2.Project = await client.labrinth.projects_v2.get('sodium')
const members = await client.labrinth.projects_v3.getMembers(project.id)
```

You can still make direct requests through the same platform layer:

```ts
const project = await client.request<Labrinth.Projects.v2.Project>('/project/sodium', {
	api: 'labrinth',
	version: 2,
})
```

### Nuxt

```ts
import { AuthFeature, CircuitBreakerFeature, NuxtCircuitBreakerStorage, NuxtBbsmcClient } from '@Bbsmc/api-client'

export const useBbsmcClient = async () => {
	const config = useRuntimeConfig()

	return new NuxtBbsmcClient({
		userAgent: 'my-nuxt-app/1.0.0',
		rateLimitKey: import.meta.server ? config.rateLimitKey : undefined,
		features: [
			new AuthFeature({
				token: process.env.Bbsmc_TOKEN,
			}),
			new CircuitBreakerFeature({
				storage: new NuxtCircuitBreakerStorage(),
			}),
		],
	})
}
```

### Tauri

```ts
import { getVersion } from '@tauri-apps/api/app'
import { AuthFeature, TauriBbsmcClient } from '@Bbsmc/api-client'

const client = new TauriBbsmcClient({
	userAgent: async () => `Bbsmc/theseus/${await getVersion()} (support@bbsmc.org.cn)`,
	features: [new AuthFeature({ token: process.env.Bbsmc_TOKEN })],
})

const project = await client.labrinth.projects_v2.get('sodium')
```

## API Modules

Modules are available as nested properties on the client:

```ts
client.labrinth.projects_v2
client.labrinth.projects_v3
client.labrinth.versions_v3
```

Types are exported from the package root:

```ts
import type { Labrinth } from '@Bbsmc/api-client'

const project: Labrinth.Projects.v3.Project = await client.labrinth.projects_v3.get('sodium')
```

## Bbsmc Hosting API Modules

- These modules are internal to Bbsmc and are only supported inside the Bbsmc Hosting panel in Bbsmc App and on bbsmc.org.cn. They should not be expected to work in third-party clients today. We are discussing how to safely expose access to your own server through these APIs in the future.

## Base URLs

By default, the client uses Bbsmc production services:

- `labrinthBaseUrl`: `https://api.bbsmc.org.cn`

Override them for staging or custom deployments:

```ts
const client = new GenericBbsmcClient({
	userAgent: 'my-app/1.0.0',
	labrinthBaseUrl: 'https://staging-api.bbsmc.org.cn',
})
```

External APIs can be targeted per request by passing a full URL as `api` and disabling auth:

```ts
await client.request('/endpoint', {
	api: 'https://example.com',
	version: 1,
	skipAuth: true,
})
```

## Features

Features wrap requests before they reach the platform implementation:

```ts
import { AuthFeature, CircuitBreakerFeature, RetryFeature } from '@Bbsmc/api-client'

const client = new GenericBbsmcClient({
	features: [new AuthFeature({ token: async () => process.env.Bbsmc_TOKEN }), new RetryFeature({ maxAttempts: 3, backoffStrategy: 'exponential' }), new CircuitBreakerFeature({ maxFailures: 3, resetTimeout: 30_000 })],
})
```

Built-in features include authentication, node auth, retries, circuit breaking, panel version headers, and verbose logging.

## Uploads

Upload endpoints return an `UploadHandle<T>` with progress and cancellation support:

```ts
const upload = client.kyros.files_v0.uploadFile(path, file)

upload.onProgress(({ progress }) => {
	console.log(Math.round(progress * 100))
})

await upload.promise
```

Uploads use `XMLHttpRequest` for progress tracking and are only available in browser-capable contexts. `NuxtBbsmcClient.upload()` throws during SSR.

## Third-Party API Typings

- This package also includes some third-party API modules and typings used by Bbsmc internals. They are not part of the stable public API surface and should be used at your own risk.

## Development

```bash
pnpm --filter @Bbsmc/api-client build
pnpm --filter @Bbsmc/api-client lint
# or pnpm prepr:frontend:lib in turborepo root.
```

When adding a module, add it to `src/modules/index.ts` so it is included in the typed client structure.

## License

Licensed under LGPL-3.0. See [LICENSE](LICENSE).
