<script setup lang="ts">
import {
	injectBbsmcClient,
	injectBbsmcServerContext,
	ServersManageBackupsPage,
} from '@Bbsmc/ui'
import { useQueryClient } from '@tanstack/vue-query'

const client = injectBbsmcClient()
const { server, serverId, worldId, isServerRunning } = injectBbsmcServerContext()
const queryClient = useQueryClient()
const flags = useFeatureFlags()

if (worldId.value) {
	try {
		await queryClient.ensureQueryData({
			queryKey: ['backups', 'list', serverId],
			queryFn: () => client.archon.backups_v1.list(serverId, worldId.value!),
			staleTime: 30_000,
		})
	} catch {
		// Let mounted layouts' useQuery surface errors; do not fail route setup.
	}
}

useHead({
	title: `Backups - ${server.value?.name ?? 'Server'} - Bbsmc`,
})
</script>

<template>
	<ServersManageBackupsPage
		:is-server-running="isServerRunning"
		:show-copy-id-action="flags.developerMode"
		:show-debug-info="flags.advancedDebugInfo"
	/>
</template>
