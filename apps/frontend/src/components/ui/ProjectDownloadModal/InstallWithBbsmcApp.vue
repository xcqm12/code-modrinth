<template>
	<div
		v-if="
			project.project_type !== 'plugin' ||
			project.loaders.some((x) => !tags.loaderData.allPluginLoaders.includes(x))
		"
		class="modrinth-app-section contents"
	>
		<div class="flex flex-col items-center">
			<ButtonStyled color="brand">
				<a
					class="!min-h-10 w-fit no-underline"
					:href="`modrinth://mod/${project.slug}`"
					@click="installWithApp"
				>
					<modrinthIcon aria-hidden="true" />
					<span class="min-w-0 text-center">
						{{ formatMessage(messages.installWithmodrinthApp) }}
					</span>
				</a>
			</ButtonStyled>
			<Accordion ref="getmodrinthAppAccordion">
				<nuxt-link class="mt-2 flex justify-center text-brand-blue hover:underline" to="/app">
					{{ formatMessage(messages.dontHavemodrinthApp) }}
				</nuxt-link>
			</Accordion>
		</div>

		<div class="flex items-center gap-4">
			<div class="flex h-[2px] w-full rounded-2xl bg-button-bg"></div>
			<span class="flex-shrink-0 text-sm font-medium text-secondary">
				{{ formatMessage(messages.downloadManually) }}
			</span>
			<div class="flex h-[2px] w-full rounded-2xl bg-button-bg"></div>
		</div>
	</div>
</template>

<script setup lang="ts">
import type { Labrinth } from '@modrinth/api-client'
import { modrinthIcon } from '@modrinth/assets'
import { ButtonStyled, defineMessages, useVIntl } from '@modrinth/ui'
import type { DisplayProjectType } from '@modrinth/utils'
import { ref } from 'vue'

import Accordion from '~/components/ui/Accordion.vue'

defineOptions({
	name: 'InstallWithmodrinthApp',
})

type DownloadModalProject = Omit<Labrinth.Projects.v2.Project, 'project_type'> & {
	project_type: DisplayProjectType
	actualProjectType: Labrinth.Projects.v2.ProjectType
}

defineProps<{
	project: DownloadModalProject
}>()

const { formatMessage } = useVIntl()
const tags = useGeneratedState()
const getmodrinthAppAccordion = ref<InstanceType<typeof Accordion> | null>(null)

const messages = defineMessages({
	installWithmodrinthApp: {
		id: 'project.download.install-with-app',
		defaultMessage: 'Install with modrinth App',
	},
	dontHavemodrinthApp: {
		id: 'project.download.no-app',
		defaultMessage: "Don't have modrinth App?",
	},
	downloadManually: {
		id: 'project.download.manually',
		defaultMessage: 'Download manually',
	},
})

function installWithApp() {
	setTimeout(() => {
		getmodrinthAppAccordion.value?.open()
	}, 1500)
}
</script>

<style lang="scss" scoped>
@media (hover: none) and (max-width: 767px) {
	.modrinth-app-section {
		display: none;
	}
}
</style>
