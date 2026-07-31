import serverSidedVue from '@vitejs/plugin-vue'
import fs from 'fs/promises'
import { defineNuxtConfig } from 'nuxt/config'
import { fileURLToPath } from 'url'
import svgLoader from 'vite-svg-loader'

import { GenericmodrinthClient, type Labrinth } from '../../packages/api-client/src/index.ts'

const STAGING_API_URL = 'https://staging-api.bbsmc.org.cn/v2/'
const PROD_API_URL = 'https://api.bbsmc.org.cn/v2/'
const STAGING_SHARED_INSTANCES_API_URL = 'https://staging-shared-instances.bbsmc.org.cn'
const PROD_SHARED_INSTANCES_API_URL = 'https://shared-instances.bbsmc.org.cn'
const API_CLIENT_SOURCE = fileURLToPath(
	new URL('../../packages/api-client/src/index.ts', import.meta.url),
)

const preloadedFonts = [
	'inter/Inter-Regular.woff2',
	'inter/Inter-Medium.woff2',
	'inter/Inter-SemiBold.woff2',
	'inter/Inter-Bold.woff2',
]

const favicons = {
	'(prefers-color-scheme:no-preference)': '/favicon-light.ico',
	'(prefers-color-scheme:light)': '/favicon-light.ico',
	'(prefers-color-scheme:dark)': '/favicon.ico',
}

const PROD_modrinth_URL = 'https://bbsmc.org.cn'
const STAGING_modrinth_URL = 'https://staging.bbsmc.org.cn'

export default defineNuxtConfig({
	srcDir: 'src/',
	alias: {
		'@bbsmc/api-client': API_CLIENT_SOURCE,
	},
	app: {
		head: {
			htmlAttrs: {
				lang: 'en',
			},
			title: 'modrinth',
			link: [
				// The type is necessary because the linter can't always compare this very nested/complex type on itself
				...preloadedFonts.map((font): object => {
					return {
						rel: 'preload',
						href: `https://cdn-raw.bbsmc.org.cn/fonts/${font}?v=3.19`,
						as: 'font',
						type: 'font/woff2',
						crossorigin: 'anonymous',
					}
				}),
				...Object.entries(favicons).map(([media, href]): object => {
					return { rel: 'icon', type: 'image/x-icon', href, media }
				}),
				...Object.entries(favicons).map(([media, href]): object => {
					return { rel: 'apple-touch-icon', type: 'image/x-icon', href, media, sizes: '64x64' }
				}),
				{
					rel: 'search',
					type: 'application/opensearchdescription+xml',
					href: '/opensearch.xml',
					title: 'modrinth mods',
				},
			],
		},
	},
	vite: {
		css: {
			preprocessorOptions: {
				scss: {
					// TODO: dont forget about this
					silenceDeprecations: ['import'],
				},
			},
		},
		ssr: {
			// https://github.com/Akryum/floating-vue/issues/809#issuecomment-1002996240
			noExternal: ['floating-vue', '@floating-ui/core', '@floating-ui/dom'],
		},
		optimizeDeps: {
			include: ['vue-router', 'floating-vue', '@floating-ui/dom'],
		},
		define: {
			global: {},
		},
		esbuild: {
			define: {
				global: 'globalThis',
			},
		},
		cacheDir: '../../node_modules/.vite/apps/knossos',
		resolve: {
			alias: {
				'@bbsmc/api-client': API_CLIENT_SOURCE,
			},
			dedupe: ['vue'],
		},
		plugins: [
			svgLoader({
				svgoConfig: {
					plugins: [
						{
							name: 'preset-default',
							params: {
								overrides: {
									removeViewBox: false,
									cleanupIds: {
										minify: false,
									},
								},
							},
						},
					],
				},
			}),
		],
		build: {
			target: 'es2020',
			rollupOptions: {
				external: ['cloudflare:workers'],
			},
		},
	},
	hooks: {
		async 'nitro:config'(nitroConfig) {
			const emailTemplates = Object.keys(
				await import('./src/templates/emails/index.ts').then((m) => m.default),
			)
			const docTemplates = Object.keys(
				await import('./src/templates/docs/index.ts').then((m) => m.default),
			)

			nitroConfig.prerender = nitroConfig.prerender || {}
			nitroConfig.prerender.routes = nitroConfig.prerender.routes || []
			for (const template of emailTemplates) {
				nitroConfig.prerender.routes.push(`/_internal/templates/email/${template}`)
			}
			for (const template of docTemplates) {
				nitroConfig.prerender.routes.push(`/_internal/templates/doc/${template}`)
			}
		},
		async 'build:before'() {
			// 30 minutes
			const TTL = 30 * 60 * 1000

			let state: Partial<Labrinth.State.GeneratedState & Record<string, any>> = {}

			try {
				state = JSON.parse(await fs.readFile('./src/generated/state.json', 'utf8'))
			} catch {
				// File doesn't exist, create folder
				await fs.mkdir('./src/generated', { recursive: true })
			}

			const API_URL = getApiUrl()
			const BUILD_API_URLS = ['https://api.modrinth.com/v2/', API_URL]

			if (
				// Skip regeneration if within TTL...
				state.lastGenerated &&
				new Date(state.lastGenerated).getTime() + TTL > new Date().getTime() &&
				// ...but only if the API URL is the same
				state.apiUrl === API_URL &&
				// ...and if no errors were caught during the last generation
				(state.errors ?? []).length === 0
			) {
				console.log(
					'Tags already recently generated. Delete apps/frontend/src/generated/state.json to force regeneration.',
				)
				return
			}

			let generatedState: Labrinth.State.GeneratedState & Record<string, any> = { errors: [] } as any

			for (const buildApiUrl of BUILD_API_URLS) {
				try {
					const client = new GenericmodrinthClient({
						labrinthBaseUrl: buildApiUrl.replace('/v2/', ''),
						userAgent: 'Knossos generator (support@bbsmc.org.cn)',
						timeout: 5000,
					})

					generatedState = await client.labrinth.state.build()
					console.log(`State generated successfully using API: ${buildApiUrl}`)
					break
				} catch (e) {
					console.warn(`State generation using ${buildApiUrl} failed: ${(e as Error).message}`)
				}
			}

			state.lastGenerated = new Date().toISOString()
			state.apiUrl = API_URL
			state = {
				...state,
				...generatedState,
			}

			await fs.writeFile('./src/generated/state.json', JSON.stringify(state))

			// throw if errors and building for prod (preview & staging allowed to have errors)
			if (
				process.env.BUILD_ENV === 'production' &&
				process.env.PREVIEW !== 'true' &&
				generatedState.errors.length > 0
			) {
				throw new Error(
					`Production build failed: State generation encountered errors. Error codes: ${JSON.stringify(generatedState.errors)}; API URL: ${API_URL}`,
				)
			}

			console.log('Tags generated!')

			const robotsContent =
				getDomain() === PROD_modrinth_URL && process.env.PREVIEW !== 'true'
					? 'User-agent: *\nDisallow: /_internal/'
					: 'User-agent: *\nDisallow: /'

			await fs.writeFile('./src/public/robots.txt', robotsContent)
		},
	},
	runtimeConfig: {
		// @ts-ignore
		apiBaseUrl: process.env.BASE_URL ?? globalThis.BASE_URL ?? getApiUrl(),
		// @ts-ignore
		rateLimitKey: process.env.RATE_LIMIT_IGNORE_KEY ?? globalThis.RATE_LIMIT_IGNORE_KEY,
		pyroBaseUrl: process.env.PYRO_BASE_URL,
		sharedInstancesBaseUrl: getSharedInstancesApiUrl(),
		intercomIdentitySecret:
			process.env.INTERCOM_IDENTITY_SECRET ??
			// @ts-ignore
			globalThis.INTERCOM_IDENTITY_SECRET,
		public: {
			apiBaseUrl: getApiUrl(),
			pyroBaseUrl: process.env.PYRO_BASE_URL,
			sharedInstancesBaseUrl: getSharedInstancesApiUrl(),
			siteUrl: getDomain(),
			intercomAppId:
				process.env.INTERCOM_APP_ID ||
				// @ts-ignore
				globalThis.INTERCOM_APP_ID ||
				'ykeritl9',
			production: isProduction(),
			cookieSecure: isProduction(),
			buildEnv: process.env.BUILD_ENV,
			preview: process.env.PREVIEW === 'true',
			featureFlagOverrides: getFeatureFlagOverrides(),

			owner: process.env.VERCEL_GIT_REPO_OWNER || 'modrinth',
			slug: process.env.VERCEL_GIT_REPO_SLUG || 'code',
			branch:
				process.env.VERCEL_GIT_COMMIT_REF ||
				process.env.CF_PAGES_BRANCH ||
				// @ts-ignore
				globalThis.CF_PAGES_BRANCH ||
				'main',
			hash:
				process.env.VERCEL_GIT_COMMIT_SHA ||
				process.env.CF_PAGES_COMMIT_SHA ||
				// @ts-ignore
				globalThis.CF_PAGES_COMMIT_SHA ||
				'unknown',

			stripePublishableKey:
				process.env.STRIPE_PUBLISHABLE_KEY ||
				globalThis.STRIPE_PUBLISHABLE_KEY ||
				'pk_test_51JbFxJJygY5LJFfKV50mnXzz3YLvBVe2Gd1jn7ljWAkaBlRz3VQdxN9mXcPSrFbSqxwAb0svte9yhnsmm7qHfcWn00R611Ce7b',
		},
	},
	typescript: {
		shim: false,
		strict: true,
		typeCheck: false,
		tsConfig: {
			compilerOptions: {
				moduleResolution: 'bundler',
				allowImportingTsExtensions: true,
			},
		},
	},
	modules: [
		'floating-vue/nuxt',
		// Sentry causes rollup-plugin-inject errors in dev, only enable in production
		...(isProduction() ? ['@sentry/nuxt/module'] : []),
	],
	floatingVue: {
		themes: {
			'ribbit-popout': {
				$extend: 'dropdown',
				placement: 'bottom-end',
				instantMove: true,
				distance: 8,
			},
			'dismissable-prompt': {
				$extend: 'dropdown',
				placement: 'bottom-start',
			},
		},
	},
	nitro: {
		rollupConfig: {
			// @ts-expect-error because of rolldown-vite - completely fine though
			plugins: [serverSidedVue()],
			external: ['cloudflare:workers'],
		},
		preset: process.env.NITRO_PRESET || 'cloudflare_module',
		cloudflare: {
			nodeCompat: true,
		},
		replace: {
			__SENTRY_RELEASE__: JSON.stringify(process.env.CF_PAGES_COMMIT_SHA || 'unknown'),
			__SENTRY_ENVIRONMENT__: JSON.stringify(process.env.BUILD_ENV || 'development'),
		},
	},
	devtools: {
		enabled: true,
	},
	css: ['~/assets/styles/tailwind.css'],
	postcss: {
		plugins: {
			tailwindcss: {},
			autoprefixer: {},
		},
	},
	routeRules: {
		'/**': {
			headers: {
				'Accept-CH': 'Sec-CH-Prefers-Color-Scheme',
				'Critical-CH': 'Sec-CH-Prefers-Color-Scheme',
			},
		},
		'/dashboard/revenue/withdraw': {
			redirect: {
				to: '/dashboard/revenue',
				statusCode: 410,
			},
		},
		'/email/**': {
			redirect: '/_internal/templates/email/**',
		},
		'/_internal/templates/email/**': {
			prerender: true,
			headers: {
				'Content-Type': 'text/html',
				'Cache-Control': 'public, max-age=3600',
			},
		},
		'/_internal/templates/doc/**': {
			prerender: true,
			headers: {
				'Content-Type': 'text/html',
				'Cache-Control': 'public, max-age=3600',
			},
		},
	},
	compatibilityDate: '2025-01-01',
	telemetry: false,
	experimental: {
		asyncContext: true,
	},
	sourcemap: { client: 'hidden' },
	sentry: {
		sourcemaps: {
			disable: true,
		},
	},
})

function getApiUrl() {
	if (process.env.NODE_ENV === 'production') {
		// @ts-ignore
		return process.env.BROWSER_BASE_URL ?? globalThis.BROWSER_BASE_URL ?? PROD_API_URL
	}
	// @ts-ignore
	return process.env.BROWSER_BASE_URL ?? globalThis.BROWSER_BASE_URL ?? STAGING_API_URL
}

function getSharedInstancesApiUrl() {
	if (process.env.NODE_ENV === 'production') {
		return (
			process.env.SHARED_INSTANCES_API_BASE_URL ??
			// @ts-ignore
			globalThis.SHARED_INSTANCES_API_BASE_URL ??
			PROD_SHARED_INSTANCES_API_URL
		)
	}
	return (
		process.env.SHARED_INSTANCES_API_BASE_URL ??
		// @ts-ignore
		globalThis.SHARED_INSTANCES_API_BASE_URL ??
		STAGING_SHARED_INSTANCES_API_URL
	)
}

function isProduction() {
	return process.env.NODE_ENV === 'production'
}

function getFeatureFlagOverrides() {
	return JSON.parse(process.env.FLAG_OVERRIDES ?? '{}')
}

function getDomain() {
	if (process.env.NODE_ENV === 'production') {
		if (process.env.HEROKU_APP_NAME) {
			return `https://${process.env.HEROKU_APP_NAME}.herokuapp.com`
		} else if (process.env.VERCEL_URL) {
			return `https://${process.env.VERCEL_URL}`
		} else if (getApiUrl() === STAGING_API_URL) {
			return STAGING_modrinth_URL
		} else {
			return PROD_modrinth_URL
		}
	} else {
		const port = process.env.PORT || 3000
		return `http://localhost:${port}`
	}
}
