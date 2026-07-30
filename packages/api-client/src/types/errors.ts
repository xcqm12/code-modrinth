/**
 * Data for API errors
 */
export type ApiErrorData = {
	/**
	 * HTTP status code (if available)
	 */
	statusCode?: number

	/**
	 * Original error that was caught
	 */
	originalError?: Error

	/**
	 * Response data from the API (if available)
	 */
	responseData?: unknown

	/**
	 * Error context (e.g., module name, operation being performed)
	 */
	context?: string
}

/**
 * Bbsmc V1 error response format
 * Used by kyros + archon APIs
 */
export type BbsmcErrorResponse = {
	/**
	 * Error code/identifier
	 */
	error: string

	/**
	 * Human-readable error description
	 */
	description: string

	/**
	 * Optional context about where the error occurred
	 */
	context?: string
}

/**
 * Type guard to check if an object is a BbsmcErrorResponse
 */
export function isBbsmcErrorResponse(obj: unknown): obj is BbsmcErrorResponse {
	if (typeof obj !== 'object' || obj === null) {
		return false
	}
	const record = obj as Record<string, unknown>
	return typeof record.error === 'string' && typeof record.description === 'string'
}
