const trimTrailingSlash = (url: string) => url.replace(/\/$/, '')

const siteUrl = trimTrailingSlash(import.meta.env.modrinth_URL || 'https://bbsmc.org.cn')
const labrinthBaseUrl = trimTrailingSlash(
	import.meta.env.modrinth_API_BASE_URL || 'https://api.bbsmc.org.cn',
)
const archonBaseUrl = trimTrailingSlash(
	import.meta.env.modrinth_ARCHON_BASE_URL || 'https://archon.bbsmc.org.cn',
)
const sharedInstancesBaseUrl = trimTrailingSlash(
	import.meta.env.SHARED_INSTANCES_API_BASE_URL || 'https://shared-instances.bbsmc.org.cn',
)

export const config = {
	siteUrl,
	stripePublishableKey:
		import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY ||
		'pk_test_51JbFxJJygY5LJFfKV50mnXzz3YLvBVe2Gd1jn7ljWAkaBlRz3VQdxN9mXcPSrFbSqxwAb0svte9yhnsmm7qHfcWn00R611Ce7b',
	labrinthBaseUrl,
	archonBaseUrl,
	sharedInstancesBaseUrl,
}
