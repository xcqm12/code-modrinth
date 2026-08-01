import { createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'

const require = createRequire(import.meta.url)

// Use CJS resolution to find nuxt (bypasses exsolve's moduleResolve which
// fails with pnpm symlinks on Node.js 24)
const nuxtEntry = require.resolve('nuxt')
const mod = await import(pathToFileURL(nuxtEntry).href)
const nuxt = mod.default || mod

// Call nuxt's own loadNuxt (not @nuxt/kit's wrapper which uses exsolve)
const instance = await nuxt.loadNuxt({
  rootDir: process.cwd(),
  overrides: { _ready: false },
})

await nuxt.build(instance)
process.exit(0)
