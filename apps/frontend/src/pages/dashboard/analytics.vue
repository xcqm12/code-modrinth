<template>
	<AnalyticsDashboard />
</template>

<script setup>
import { commonProjectSettingsMessages, useVIntl } from '@bbsmc/ui'

import AnalyticsDashboard from '~/components/analytics-dashboard/index.vue'

const { formatMessage } = useVIntl()

definePageMeta({
	middleware: 'auth',
})

useHead({
	title: () => `${formatMessage(commonProjectSettingsMessages.analytics)} - modrinth`,
})
</script>
