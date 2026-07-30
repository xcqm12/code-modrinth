<script setup lang="ts">
import type { Labrinth } from '@Bbsmc/api-client'
import { ServerStackIcon } from '@Bbsmc/assets'
import { injectBbsmcClient, ServersManagePageIndex } from '@Bbsmc/ui'
import { useQuery } from '@tanstack/vue-query'
import { computed } from 'vue'

import { useRootBreadcrumb } from '@/providers/breadcrumbs'

import { config } from '../config'

const stripePublishableKey = (config.stripePublishableKey as string) || ''

const client = injectBbsmcClient()

useRootBreadcrumb({
	slot: 'root',
	id: 'servers',
	label: 'Servers',
	to: '/hosting/manage/',
	visual: { type: 'icon', component: ServerStackIcon },
})

const { data: products } = useQuery({
	queryKey: ['billing', 'products'],
	queryFn: () => client.labrinth.billing_internal.getProducts(),
})

const resolvedProducts = computed<Labrinth.Billing.Internal.Product[]>(() => products.value ?? [])
</script>

<template>
	<ServersManagePageIndex
		:stripe-publishable-key="stripePublishableKey"
		:products="resolvedProducts"
	/>
</template>
