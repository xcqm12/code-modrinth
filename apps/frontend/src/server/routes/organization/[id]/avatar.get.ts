import { type Labrinth, BbsmcApiError } from '@Bbsmc/api-client'

import { useServerBbsmcClient } from '~/server/utils/api-client'

export default defineEventHandler(async (event) => {
	const id = getRouterParam(event, 'id')

	if (!id) {
		throw createError({
			statusCode: 400,
			message: 'Missing organization',
		})
	}

	const client = useServerBbsmcClient({ event })

	let organization: Labrinth.Organizations.v3.Organization
	try {
		organization = await client.labrinth.organizations_v3.get(id)
	} catch (error) {
		if (error instanceof BbsmcApiError && error.statusCode === 404) {
			throw createError({
				statusCode: 404,
				message: 'Organization not found',
			})
		}

		throw createError({
			statusCode: 502,
			message: 'Failed to resolve organization avatar',
		})
	}

	if (!organization.icon_url) {
		throw createError({
			statusCode: 404,
			message: 'Organization avatar not found',
		})
	}

	setHeader(event, 'cache-control', 'public, max-age=300, s-maxage=600')
	return sendRedirect(event, organization.icon_url, 302)
})
