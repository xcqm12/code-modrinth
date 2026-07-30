import { provideBbsmcClient } from '@Bbsmc/ui'

import { createBbsmcClient } from '~/helpers/api.ts'

export function setupBbsmcClientProvider(auth: Awaited<ReturnType<typeof useAuth>>) {
	const config = useRuntimeConfig()
	const client = createBbsmcClient(auth, {
		apiBaseUrl: config.public.apiBaseUrl.replace('/v2/', '/'),
		archonBaseUrl: config.public.pyroBaseUrl.replace('/v2/', '/'),
		sharedInstancesBaseUrl: config.public.sharedInstancesBaseUrl,
		rateLimitKey: config.rateLimitKey,
	})
	provideBbsmcClient(client)
	return client
}
