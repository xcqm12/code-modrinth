import type { ApiErrorData, modrinthErrorResponse } from '../types/errors'
import { ismodrinthErrorResponse } from '../types/errors'

/**
 * Base error class for all modrinth API errors
 */
export class modrinthApiError extends Error {
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
		this.name = 'modrinthApiError'

		this.statusCode = data?.statusCode
		this.originalError = data?.originalError
		this.responseData = data?.responseData
		this.context = data?.context

		// Maintains proper stack trace for where our error was thrown (only available on V8)
		if (Error.captureStackTrace) {
			Error.captureStackTrace(this, modrinthApiError)
		}
	}

	/**
	 * Create a modrinthApiError from an unknown error
	 */
	static fromUnknown(error: unknown, context?: string): modrinthApiError {
		if (error instanceof modrinthApiError) {
			return error
		}

		if (error instanceof Error) {
			return new modrinthApiError(error.message, {
				originalError: error,
				context,
			})
		}

		return new modrinthApiError(String(error), { context })
	}
}

/**
 * Error class for modrinth server errors (kyros/archon)
 * Extends modrinthApiError with V1 error response parsing
 */
export class modrinthServerError extends modrinthApiError {
	/**
	 * V1 error information (if available)
	 */
	readonly v1Error?: modrinthErrorResponse

	constructor(message: string, data?: ApiErrorData & { v1Error?: modrinthErrorResponse }) {
		// If we have a V1 error, format the message nicely
		let errorMessage = message
		if (data?.v1Error) {
			errorMessage = `[${data.v1Error.error}] ${data.v1Error.description}`
			if (data.v1Error.context) {
				errorMessage = `${data.v1Error.context}: ${errorMessage}`
			}
		}

		super(errorMessage, data)
		this.name = 'modrinthServerError'
		this.v1Error = data?.v1Error

		if (Error.captureStackTrace) {
			Error.captureStackTrace(this, modrinthServerError)
		}
	}

	/**
	 * Create a modrinthServerError from response data
	 */
	static fromResponse(
		statusCode: number,
		responseData: unknown,
		context?: string,
	): modrinthServerError {
		const v1Error = ismodrinthErrorResponse(responseData) ? responseData : undefined

		let message = `HTTP ${statusCode}`
		if (v1Error) {
			message = v1Error.description
		} else if (typeof responseData === 'string') {
			message = responseData
		}

		return new modrinthServerError(message, {
			statusCode,
			responseData,
			context,
			v1Error,
		})
	}

	/**
	 * Create a modrinthServerError from an unknown error
	 */
	static fromUnknown(error: unknown, context?: string): modrinthServerError {
		if (error instanceof modrinthServerError) {
			return error
		}

		if (error instanceof modrinthApiError) {
			return new modrinthServerError(error.message, {
				statusCode: error.statusCode,
				originalError: error.originalError,
				responseData: error.responseData,
				context: context ?? error.context,
			})
		}

		if (error instanceof Error) {
			return new modrinthServerError(error.message, {
				originalError: error,
				context,
			})
		}

		return new modrinthServerError(String(error), { context })
	}
}
