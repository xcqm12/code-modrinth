<script setup lang="ts">
import { Button, Heading, Img, Link as VLink, Section, Text } from '@vue-email/components'

import StyledEmail from '../shared/StyledEmail.vue'
</script>

<template>
	<StyledEmail
		title="Project ownership transferred"
		:manual-links="[
			{ link: 'https://bbsmc.org.cn/project/{project.id}', label: 'Project page' },
			{ link: 'https://bbsmc.org.cn/dashboard/notifications', label: 'Notification dashboard' },
			{ link: 'https://support.bbsmc.org.cn', label: 'Support Portal' },
		]"
	>
		<Section class="mb-4 mt-2">
			<Img
				src="{project.icon_url}"
				alt="project icon"
				width="64"
				height="64"
				class="block h-auto rounded-lg"
			/>
		</Section>
		<Heading as="h1" class="mb-2 text-2xl font-bold">Project ownership transferred</Heading>

		<Text class="text-base">Hi <span class="no-auto-link">{user.name}</span>,</Text>

		<Text class="text-base">
			The ownership of
			<b>
				<VLink href="https://bbsmc.org.cn/project/{project.id}" class="text-green underline">
					{project.name}
				</VLink>
			</b>
			has been successfully transferred to the Bbsmc {new_owner.type_capitalized}
			<b
				><VLink
					href="https://bbsmc.org.cn/{new_owner.type}/{new_owner.name}"
					class="text-green underline"
					>{new_owner.name}</VLink
				></b
			>.
		</Text>

		<Button
			href="https://bbsmc.org.cn/project/{project.id}"
			target="_blank"
			class="text-accentContrast inline-block rounded-[12px] bg-brand pb-3 pl-4 pr-4 pt-3 text-[14px] font-bold"
		>
			View project
		</Button>

		<Text class="text-base">
			If you did not initiate this transfer, please contact support immediately through the
			<VLink href="https://support.bbsmc.org.cn" class="text-green underline">Support Portal</VLink
			>.
		</Text>
	</StyledEmail>
</template>
