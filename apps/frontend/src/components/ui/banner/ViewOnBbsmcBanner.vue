<script setup lang="ts">
import { PagewideBanner } from '@bbsmc/ui'

const flags = useFeatureFlags()
const route = useRoute()

const url = computed(() => `https://bbsmc.org.cn${route.fullPath}`)

const bannerRoot = ref<HTMLElement | null>(null)

function onProdLinkClick(e: MouseEvent) {
	e.preventDefault()
	const el = bannerRoot.value
	if (el) {
		const { height } = el.getBoundingClientRect()
		window.scrollBy({ top: Math.ceil(height), behavior: 'auto' })
	}
	window.open(url.value, '_blank', 'noopener,noreferrer')
}
</script>

<template>
	<div v-if="flags.showViewProdRouteBanner || flags.showAllBanners" ref="bannerRoot">
		<PagewideBanner variant="info" slim>
			<template #description>
				<span>
					View route on production:
					<a
						:href="url"
						target="_blank"
						rel="noopener noreferrer"
						class="text-link"
						@click="onProdLinkClick"
					>
						{{ url }}
					</a>
				</span>
			</template>
		</PagewideBanner>
	</div>
</template>
