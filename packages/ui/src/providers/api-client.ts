import type { AbstractmodrinthClient } from '@modrinth/api-client'

import { createContext } from './create-context'

export const [injectmodrinthClient, providemodrinthClient] = createContext<AbstractmodrinthClient>(
	'root',
	'modrinthClient',
)
