import { providemodrinthClient } from '@bbsmc/ui'

import { createmodrinthClient } from '~/helpers/api.ts'

export function setupmodrinthClientProvider(auth: Awaited<ReturnType<typeof useAuth>>) {
	const config = useRuntimeConfig()
	const client = createmodrinthClient(auth, {
		apiBaseUrl: config.public.apiBaseUrl.replace('/v2/', '/'),
		archonBaseUrl: config.public.pyroBaseUrl.replace('/v2/', '/'),
		sharedInstancesBaseUrl: config.public.sharedInstancesBaseUrl,
		rateLimitKey: config.rateLimitKey,
	})
	providemodrinthClient(client)
	return client
}
