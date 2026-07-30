import type { ApiErrorData, BbsmcErrorResponse } from '../types/errors'
import { isBbsmcErrorResponse } from '../types/errors'

/**
 * Base error class for all Bbsmc API errors
 */
export class BbsmcApiError extends Error {
	/**
	 * HTTP status code (if available)
	 */
	readonly statusCode?: number

	/**
	 * Original error that was caught
	 */
	readonly originalError?: Error

	/**
	 * Response data from the API (if available)
	 */
	readonly responseData?: unknown

	/**
	 * Error context (e.g., module name, operation being performed)
	 */
	readonly context?: string

	constructor(message: string, data?: ApiErrorData) {
		super(message)
		this.name = 'BbsmcApiError'

		this.statusCode = data?.statusCode
		this.originalError = data?.originalError
		this.responseData = data?.responseData
		this.context = data?.context

		// Maintains proper stack trace for where our error was thrown (only available on V8)
		if (Error.captureStackTrace) {
			Error.captureStackTrace(this, BbsmcApiError)
		}
	}

	/**
	 * Create a BbsmcApiError from an unknown error
	 */
	static fromUnknown(error: unknown, context?: string): BbsmcApiError {
		if (error instanceof BbsmcApiError) {
			return error
		}

		if (error instanceof Error) {
			return new BbsmcApiError(error.message, {
				originalError: error,
				context,
			})
		}

		return new BbsmcApiError(String(error), { context })
	}
}

/**
 * Error class for Bbsmc server errors (kyros/archon)
 * Extends BbsmcApiError with V1 error response parsing
 */
export class BbsmcServerError extends BbsmcApiError {
	/**
	 * V1 error information (if available)
	 */
	readonly v1Error?: BbsmcErrorResponse

	constructor(message: string, data?: ApiErrorData & { v1Error?: BbsmcErrorResponse }) {
		// If we have a V1 error, format the message nicely
		let errorMessage = message
		if (data?.v1Error) {
			errorMessage = `[${data.v1Error.error}] ${data.v1Error.description}`
			if (data.v1Error.context) {
				errorMessage = `${data.v1Error.context}: ${errorMessage}`
			}
		}

		super(errorMessage, data)
		this.name = 'BbsmcServerError'
		this.v1Error = data?.v1Error

		if (Error.captureStackTrace) {
			Error.captureStackTrace(this, BbsmcServerError)
		}
	}

	/**
	 * Create a BbsmcServerError from response data
	 */
	static fromResponse(
		statusCode: number,
		responseData: unknown,
		context?: string,
	): BbsmcServerError {
		const v1Error = isBbsmcErrorResponse(responseData) ? responseData : undefined

		let message = `HTTP ${statusCode}`
		if (v1Error) {
			message = v1Error.description
		} else if (typeof responseData === 'string') {
			message = responseData
		}

		return new BbsmcServerError(message, {
			statusCode,
			responseData,
			context,
			v1Error,
		})
	}

	/**
	 * Create a BbsmcServerError from an unknown error
	 */
	static fromUnknown(error: unknown, context?: string): BbsmcServerError {
		if (error instanceof BbsmcServerError) {
			return error
		}

		if (error instanceof BbsmcApiError) {
			return new BbsmcServerError(error.message, {
				statusCode: error.statusCode,
				originalError: error.originalError,
				responseData: error.responseData,
				context: context ?? error.context,
			})
		}

		if (error instanceof Error) {
			return new BbsmcServerError(error.message, {
				originalError: error,
				context,
			})
		}

		return new BbsmcServerError(String(error), { context })
	}
}
