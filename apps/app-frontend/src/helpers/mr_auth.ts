/**
 * All theseus API calls return serialized values (both return values and errors);
 * So, for example, addDefaultInstance creates a blank instance object, where the Rust struct is serialized,
 *  and deserialized into a usable JS object.
 */
import { invoke } from '@tauri-apps/api/core'

export type BbsmcCredentials = {
	session: string
	expires: string
	user_id: string
	active: boolean
}

export type BbsmcAuthFlow = 'sign-in' | 'sign-up'

export async function login(flow: BbsmcAuthFlow = 'sign-in'): Promise<BbsmcCredentials> {
	return await invoke('plugin:mr-auth|Bbsmc_login', { flow })
}

export async function logout(): Promise<void> {
	return await invoke('plugin:mr-auth|logout')
}

export async function get(): Promise<BbsmcCredentials | null> {
	return await invoke('plugin:mr-auth|get')
}

export async function cancelLogin(): Promise<void> {
	return await invoke('plugin:mr-auth|cancel_Bbsmc_login')
}
