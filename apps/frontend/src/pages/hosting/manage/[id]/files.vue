<script setup lang="ts">
import {
	injectmodrinthClient,
	injectmodrinthServerContext,
	ServersManageFilesPage,
} from '@bbsmc/ui'
import { useQueryClient } from '@tanstack/vue-query'

const client = injectmodrinthClient()
const { server, serverId } = injectmodrinthServerContext()
const queryClient = useQueryClient()
const flags = useFeatureFlags()

try {
	await queryClient.ensureQueryData({
		queryKey: ['files', serverId, '/'],
		queryFn: () => client.kyros.files_v0.listDirectory('/', 1, 2000),
		staleTime: 30_000,
	})
} catch {
	// Let mounted layouts' useQuery surface errors; do not fail route setup.
}

useHead({
	title: computed(() => `Files - ${server.value?.name ?? 'Server'} - modrinth`),
})
</script>

<template>
	<ServersManageFilesPage
		:show-debug-info="flags.advancedDebugInfo"
		:show-refresh-button="flags.FilesRefreshButton"
	/>
</template>
