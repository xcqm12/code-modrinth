import type { AbstractBbsmcClient } from '@Bbsmc/api-client'

import { STALE_TIME } from './project'

export const versionQueryOptions = {
	v3: (versionId: string, client: AbstractBbsmcClient) => ({
		queryKey: ['version', 'v3', versionId] as const,
		queryFn: () => client.labrinth.versions_v3.getVersion(versionId),
		staleTime: STALE_TIME,
	}),

	fromProject: (projectId: string, versionIdOrNumber: string, client: AbstractBbsmcClient) => ({
		queryKey: ['project', projectId, 'version', 'v3', versionIdOrNumber] as const,
		queryFn: () =>
			client.labrinth.versions_v3.getVersionFromIdOrNumber(projectId, versionIdOrNumber),
		staleTime: STALE_TIME,
	}),
}
