import type { AbstractmodrinthClient } from '@bbsmc/api-client'

import { createContext } from './create-context'

export const [injectmodrinthClient, providemodrinthClient] = createContext<AbstractmodrinthClient>(
	'root',
	'modrinthClient',
)
