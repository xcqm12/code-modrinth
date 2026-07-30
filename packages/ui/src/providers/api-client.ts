import type { AbstractBbsmcClient } from '@Bbsmc/api-client'

import { createContext } from './create-context'

export const [injectBbsmcClient, provideBbsmcClient] = createContext<AbstractBbsmcClient>(
	'root',
	'BbsmcClient',
)
