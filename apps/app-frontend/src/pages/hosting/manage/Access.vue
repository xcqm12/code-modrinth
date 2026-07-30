<script setup lang="ts">
import {
	injectBbsmcClient,
	injectBbsmcServerContext,
	ServersManageAccessPage,
} from '@Bbsmc/ui'
import { useQueryClient } from '@tanstack/vue-query'

const client = injectBbsmcClient()
const { serverId } = injectBbsmcServerContext()
const queryClient = useQueryClient()

try {
	await Promise.all([
		queryClient.ensureQueryData({
			queryKey: ['servers', 'users', 'v1', serverId],
			queryFn: () => client.archon.server_users_v1.list(serverId),
			staleTime: 30_000,
		}),
		queryClient.ensureQueryData({
			queryKey: ['servers', 'v1', 'detail', serverId],
			queryFn: () => client.archon.servers_v1.get(serverId),
			staleTime: 30_000,
		}),
	])
} catch {
	// Let mounted layouts' useQuery surface errors; do not fail route setup.
}

function userProfileLink(username: string) {
	return `/user/${encodeURIComponent(username)}`
}
</script>

<template>
	<ServersManageAccessPage :user-profile-link="userProfileLink" />
</template>
