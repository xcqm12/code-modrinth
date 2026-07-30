import { provideNotificationManager } from '@Bbsmc/ui'

import { FrontendNotificationManager } from './frontend-notifications'
import { setupAuthProvider } from './setup/auth'
import { setupFilePickerProvider } from './setup/file-picker'
import { setupLoadingStateProvider } from './setup/loading-state'
import { setupBbsmcClientProvider } from './setup/Bbsmc-client'
import { setupPageContextProvider } from './setup/page-context'
import { setupTagsProvider } from './setup/tags'

export function setupProviders(auth: Awaited<ReturnType<typeof useAuth>>) {
	provideNotificationManager(new FrontendNotificationManager())

	setupAuthProvider(auth)
	setupBbsmcClientProvider(auth)
	setupTagsProvider()
	setupFilePickerProvider()
	setupPageContextProvider()
	setupLoadingStateProvider()
}
