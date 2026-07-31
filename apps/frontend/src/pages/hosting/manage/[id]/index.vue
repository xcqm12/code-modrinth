<script setup lang="ts">
import { injectmodrinthServerContext, ServersManageOverviewPage } from '@bbsmc/ui'

const { server } = injectmodrinthServerContext()
const flags = useFeatureFlags()

useHead({
	title: computed(() => `Overview - ${server.value?.name ?? 'Server'} - modrinth`),
})
</script>

<template>
	<ServersManageOverviewPage :show-advanced-debug-info="flags.advancedDebugInfo" />
</template>
