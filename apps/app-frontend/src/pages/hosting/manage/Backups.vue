<script setup lang="ts">
import {
	injectmodrinthClient,
	injectmodrinthServerContext,
	ServersManageBackupsPage,
} from '@modrinth/ui'
import { useQueryClient } from '@tanstack/vue-query'

const client = injectmodrinthClient()
const { serverId, worldId, isServerRunning } = injectmodrinthServerContext()
const queryClient = useQueryClient()

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
</script>

<template>
	<ServersManageBackupsPage :is-server-running="isServerRunning" />
</template>
