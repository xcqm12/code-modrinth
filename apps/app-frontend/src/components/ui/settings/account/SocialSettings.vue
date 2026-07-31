<template>
	<AccountSocialSettings
		:get-blocked-users="get_blocked_users"
		:get-users="getUsers"
		:unblock-user="unblock_user"
	/>
</template>

<script setup lang="ts">
import type { Labrinth } from '@modrinth/api-client'
import { AccountSocialSettings, injectmodrinthClient } from '@modrinth/ui'

import { get_blocked_users, unblock_user } from '@/helpers/users'

const client = injectmodrinthClient()

function getUsers(userIds: string[]): Promise<Labrinth.Users.v2.User[]> {
	return client.labrinth.users_v2.getMultiple(userIds)
}
</script>
