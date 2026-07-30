<script setup lang="ts">
import {
	injectBbsmcClient,
	injectBbsmcServerContext,
	ServersManageFilesPage,
} from '@Bbsmc/ui'
import { useQueryClient } from '@tanstack/vue-query'

const client = injectBbsmcClient()
const { serverId } = injectBbsmcServerContext()
const queryClient = useQueryClient()

try {
	await queryClient.ensureQueryData({
		queryKey: ['files', serverId, '/'],
		queryFn: () => client.kyros.files_v0.listDirectory('/', 1, 2000),
		staleTime: 30_000,
	})
} catch {
	// Let mounted layouts' useQuery surface errors; do not fail route setup.
}
</script>

<template>
	<ServersManageFilesPage />
</template>
