ARG NODE_VERSION=24-alpine

FROM node:${NODE_VERSION} AS builder
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.33.2 --activate

COPY pnpm-lock.yaml pnpm-workspace.yaml package.json turbo.jsonc .npmrc ./
COPY packages/api-client packages/api-client
COPY packages/assets packages/assets
COPY packages/blog packages/blog
COPY packages/moderation packages/moderation
COPY packages/ui packages/ui
COPY packages/utils packages/utils
COPY packages/tooling-config packages/tooling-config
COPY patches patches
ARG CACHE_BUSTER=20260801
COPY apps/frontend apps/frontend

RUN cp apps/frontend/.env.prod apps/frontend/.env

ENV NODE_OPTIONS="--max-old-space-size=4096"
RUN pnpm install --frozen-lockfile --ignore-scripts

# Workaround: exsolve (used by @nuxt/kit's loadNuxt) uses Node's moduleResolve which
# walks up node_modules from cwd. In pnpm's isolated mode, nuxt lives in .pnpm and
# is NOT at /app/node_modules/nuxt, so resolution fails with "Cannot find any nuxt version".
# Create a symlink at project root so moduleResolve finds it when walking up from apps/frontend.
RUN if [ ! -e node_modules/nuxt ]; then \
      NUXT_DIR=$(ls -d node_modules/.pnpm/nuxt@*/node_modules/nuxt 2>/dev/null | head -1); \
      if [ -n "$NUXT_DIR" ]; then \
        ln -sf "$NUXT_DIR" node_modules/nuxt; \
        echo "Created symlink: node_modules/nuxt -> $NUXT_DIR"; \
      else \
        echo "WARNING: nuxt not found in .pnpm, resolution may fail"; \
      fi; \
    else \
      echo "node_modules/nuxt already exists"; \
    fi

# Also patch @nuxt/kit to search from project root as a fallback (busybox-sed compatible pattern)
RUN find node_modules -path "*/@nuxt/kit/dist/index.mjs" -exec sed -i 's|from: .directoryToURL(opts.cwd).|from: [directoryToURL(opts.cwd), directoryToURL(resolve(opts.cwd, "../.."))]|g' {} \;

RUN pnpm --filter @modrinth/api-client run build

ARG NODE_OPTIONS="--max-old-space-size=6144"
ARG BASE_URL=https://api.bbsmc.org.cn/v2/
ARG BROWSER_BASE_URL=https://api.bbsmc.org.cn/v2/
ARG PYRO_BASE_URL=https://archon.bbsmc.org.cn
ARG SHARED_INSTANCES_API_BASE_URL=https://shared-instances.bbsmc.org.cn

ENV NODE_OPTIONS=${NODE_OPTIONS}
ENV NITRO_PRESET=node_server
ENV NITRO_PRERENDER_PARALLEL=2
ENV BUILD_ENV=production
ENV PREVIEW=true
ENV BASE_URL=${BASE_URL}
ENV BROWSER_BASE_URL=${BROWSER_BASE_URL}
ENV PYRO_BASE_URL=${PYRO_BASE_URL}
ENV SHARED_INSTANCES_API_BASE_URL=${SHARED_INSTANCES_API_BASE_URL}

RUN pnpm --filter @modrinth/frontend build

FROM node:${NODE_VERSION}
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.33.2 --activate

COPY --from=builder /app/apps/frontend/.output ./.output
COPY --from=builder /app/apps/frontend/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules

EXPOSE 3000
ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000

CMD ["node", ".output/server/index.mjs"]
