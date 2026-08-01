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
COPY apps/frontend apps/frontend

RUN cp apps/frontend/.env.prod apps/frontend/.env

ENV NODE_OPTIONS="--max-old-space-size=4096"
RUN pnpm install --frozen-lockfile --ignore-scripts
RUN pnpm --filter @modrinth/api-client run build
# Replace nuxt symlink with real directory copy so exsolve/moduleResolve can resolve it
RUN if [ -L apps/frontend/node_modules/nuxt ] || [ -e apps/frontend/node_modules/nuxt ]; then \
        cp -rL apps/frontend/node_modules/nuxt /tmp/nuxt_copy && \
        rm -rf apps/frontend/node_modules/nuxt && \
        mv /tmp/nuxt_copy apps/frontend/node_modules/nuxt; \
    fi

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
