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

# Workaround: pnpm isolated mode places packages in .pnpm, not at direct paths.
# exsolve (used by @nuxt/cli's loadKit) uses Node's moduleResolve which walks up
# node_modules from cwd but cannot resolve through .pnpm structure.
# Create symlinks at project root so moduleResolve finds them.
RUN for pkg in nuxt @nuxt/kit; do \
      PKG_DIR=$(ls -d node_modules/.pnpm/$(echo "$pkg" | tr '/' '+')@*/node_modules/$pkg 2>/dev/null | head -1); \
      if [ -n "$PKG_DIR" ]; then \
        mkdir -p node_modules/$(dirname $pkg) 2>/dev/null; \
        ln -sf "$PKG_DIR" node_modules/$pkg; \
        echo "Created symlink: node_modules/$pkg -> $PKG_DIR"; \
      else \
        echo "WARNING: $pkg not found in .pnpm, resolution may fail"; \
      fi; \
    done

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
