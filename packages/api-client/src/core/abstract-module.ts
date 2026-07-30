import type { AbstractBbsmcClient } from './abstract-client'

export abstract class AbstractModule {
	protected client: AbstractBbsmcClient

	public constructor(client: AbstractBbsmcClient) {
		this.client = client
	}

	/**
	 * Get the module's name, used for error reporting & for module field generation.
	 * @returns Module name
	 */
	public abstract getModuleID(): string
}
