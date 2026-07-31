import { attributionQuickReplies } from '@bbsmc/moderation'
import { provideAttributionModeration } from '@bbsmc/ui'

export function setupAttributionModerationProvider() {
	provideAttributionModeration({ attributionQuickReplies })
}
