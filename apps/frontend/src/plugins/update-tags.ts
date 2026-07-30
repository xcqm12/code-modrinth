import type { Labrinth } from '@Bbsmc/api-client'
import type { GeneratedState } from '~/composables/generated'

export default defineNuxtPlugin(async () => {
	try {
		const [categories, loaders] = await Promise.all([
			$fetch<Labrinth.Tags.v2.Category[]>('/api/tags/categories'),
			$fetch<Labrinth.Tags.v2.Loader[]>('/api/tags/loaders'),
		])

		const state = useState<GeneratedState>('generatedState')

		if (state.value) {
			if (categories && categories.length > 0) {
				state.value.categories = categories
			}
			if (loaders && loaders.length > 0) {
				state.value.loaders = loaders
			}
		}
	} catch (error) {
		console.error('[Tag Updater] Failed to fetch categories/loaders:', error)
	}
})
