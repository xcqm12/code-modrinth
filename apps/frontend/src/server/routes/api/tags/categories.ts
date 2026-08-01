import type { Labrinth } from '@modrinth/api-client'

import { useServermodrinthClient } from '~/server/utils/api-client'

const CACHE_MAX_AGE = 60 * 10

export default defineCachedEventHandler(
	async (event) => {
		const client = useServermodrinthClient({ event })

		const response = await client.request<Labrinth.Tags.v2.Category[]>('/tag/category', {
			api: 'labrinth',
			version: 2,
			method: 'GET',
		})

		if (!response || !Array.isArray(response)) {
			throw createError({ statusCode: 502, message: 'Invalid response from API' })
		}

		return response
	},
	{
		maxAge: CACHE_MAX_AGE,
		name: 'categories',
		getKey: () => 'categories',
	},
)
