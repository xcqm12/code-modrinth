import { attributionQuickReplies } from '@Bbsmc/moderation'
import { provideAttributionModeration } from '@Bbsmc/ui'

export function setupAttributionModerationProvider() {
	provideAttributionModeration({ attributionQuickReplies })
}
