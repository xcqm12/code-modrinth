<template>
	<Admonition
		type="info"
		inline-actions
		:header="formatMessage(messages.sharedInstanceUpdateAvailableHeader)"
	>
		{{ formatMessage(messages.sharedInstanceUpdateAvailableBody, { name: instanceName }) }}
		<template #actions>
			<ButtonStyled color="blue">
				<button class="!h-10" @click="emit('review', $event)">
					<DownloadIcon aria-hidden="true" />
					{{ formatMessage(messages.sharedInstanceReviewUpdateButton) }}
				</button>
			</ButtonStyled>
		</template>
	</Admonition>
</template>

<script setup lang="ts">
import { DownloadIcon } from '@Bbsmc/assets'
import { Admonition, ButtonStyled, useVIntl } from '@Bbsmc/ui'

import { instanceAdmonitionsMessages as messages } from './instance-admonitions-messages'

defineProps<{
	instanceName: string
}>()

const emit = defineEmits<{
	review: [event: MouseEvent]
}>()

const { formatMessage } = useVIntl()
</script>
