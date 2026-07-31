import config from '@bbsmc/tooling-config/eslint/nuxt.mjs'

export default config.append([
	{
		ignores: ['dist/'],
	},
])
