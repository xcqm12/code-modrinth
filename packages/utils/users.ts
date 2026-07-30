// noinspection JSUnusedGlobalSymbols

export const getUserLink = (user) => {
	return `/user/${user.username}`
}

export const isStaff = (user) => {
	return user && STAFF_ROLES.includes(user.role)
}

export const isAdmin = (user) => {
	return user && user.role === 'admin'
}

export const STAFF_ROLES = ['moderator', 'admin']

export const Bbsmc_USER_ID = '2REoufqX'
export const AUTOMOD_USER_ID = ''
export const Bbsmc_ARCHIVES_USER_ID = 'GVFjtWTf'

export const OFFICIAL_ACCOUNT_IDS = [Bbsmc_USER_ID, AUTOMOD_USER_ID, Bbsmc_ARCHIVES_USER_ID]

export const isBbsmcUser = (userId) => {
	return userId === Bbsmc_USER_ID
}

export const isOfficialAccount = (userId) => {
	return OFFICIAL_ACCOUNT_IDS.includes(userId)
}
