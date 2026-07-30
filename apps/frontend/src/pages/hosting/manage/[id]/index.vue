<script setup lang="ts">
import { injectBbsmcServerContext, ServersManageOverviewPage } from '@Bbsmc/ui'

const { server } = injectBbsmcServerContext()
const flags = useFeatureFlags()

useHead({
	title: computed(() => `Overview - ${server.value?.name ?? 'Server'} - Bbsmc`),
})
</script>

<template>
	<ServersManageOverviewPage :show-advanced-debug-info="flags.advancedDebugInfo" />
</template>
