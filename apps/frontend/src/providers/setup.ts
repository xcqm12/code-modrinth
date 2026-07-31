import { provideNotificationManager } from '@modrinth/ui'

import { FrontendNotificationManager } from './frontend-notifications'
import { setupAuthProvider } from './setup/auth'
import { setupFilePickerProvider } from './setup/file-picker'
import { setupLoadingStateProvider } from './setup/loading-state'
import { setupmodrinthClientProvider } from './setup/modrinth-client'
import { setupPageContextProvider } from './setup/page-context'
import { setupTagsProvider } from './setup/tags'

export function setupProviders(auth: Awaited<ReturnType<typeof useAuth>>) {
	provideNotificationManager(new FrontendNotificationManager())

	setupAuthProvider(auth)
	setupmodrinthClientProvider(auth)
	setupTagsProvider()
	setupFilePickerProvider()
	setupPageContextProvider()
	setupLoadingStateProvider()
}
