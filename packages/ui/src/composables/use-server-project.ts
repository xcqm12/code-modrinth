import type { Archon } from '@bbsmc/api-client'
import { useQuery } from '@tanstack/vue-query'
import { computed, type ComputedRef } from 'vue'

import { injectmodrinthClient } from '#ui/providers'

// TODO: Remove and use v1
export function useServerProject(
	upstream: ComputedRef<Archon.Servers.v0.Server['upstream'] | null>,
) {
	const client = injectmodrinthClient()

	return useQuery({
		queryKey: computed(() => ['servers', 'project', upstream.value?.project_id ?? null]),
		queryFn: () => client.labrinth.projects_v2.get(upstream.value!.project_id!),
		enabled: computed(() => !!upstream.value?.project_id),
	})
}
