<template>
	<section v-if="auth.user" class="universal-card">
		<AccountSocialSettings
			:get-blocked-users="getBlockedUsers"
			:get-users="getUsers"
			:unblock-user="unblockUser"
		/>
	</section>
</template>

<script setup lang="ts">
import type { Labrinth } from '@Bbsmc/api-client'
import {
	AccountSocialSettings,
	commonSettingsMessages,
	injectBbsmcClient,
	useVIntl,
} from '@Bbsmc/ui'

definePageMeta({
	middleware: 'auth',
})

const auth = await useAuth()
const client = injectBbsmcClient()
const { formatMessage } = useVIntl()

function getBlockedUsers(): Promise<Labrinth.BlockedUsers.v3.BlockedUserId[]> {
	return client.labrinth.blocked_users_v3.list()
}

function getUsers(userIds: string[]): Promise<Labrinth.Users.v2.User[]> {
	return client.labrinth.users_v2.getMultiple(userIds)
}

function unblockUser(userId: string): Promise<void> {
	return client.labrinth.blocked_users_v3.unblock(userId)
}

useHead({
	title: () => `${formatMessage(commonSettingsMessages.social)} - Bbsmc`,
})
</script>
