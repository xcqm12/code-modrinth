import type { AbstractmodrinthClient } from './abstract-client'

export abstract class AbstractModule {
	protected client: AbstractmodrinthClient

	public constructor(client: AbstractmodrinthClient) {
		this.client = client
	}

	/**
	 * Get the module's name, used for error reporting & for module field generation.
	 * @returns Module name
	 */
	public abstract getModuleID(): string
}
