FROM node:24-alpine AS builder
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.33.2 --activate

COPY pnpm-lock.yaml pnpm-workspace.yaml package.json turbo.jsonc ./
COPY packages/api-client packages/api-client
COPY packages/assets packages/assets
COPY packages/blog packages/blog
COPY packages/moderation packages/moderation
COPY packages/ui packages/ui
COPY packages/utils packages/utils
COPY packages/tooling-config packages/tooling-config
COPY patches patches
COPY apps/frontend apps/frontend

# 使用生产环境配置
RUN cp apps/frontend/.env.prod apps/frontend/.env

RUN pnpm install --frozen-lockfile

ENV NODE_OPTIONS="--max-old-space-size=4096"
ENV NITRO_PRESET=node_server
ENV BUILD_ENV=production
ENV PREVIEW=true
ENV BASE_URL=https://bbsmc.org.cn/api/v2/
ENV BROWSER_BASE_URL=https://bbsmc.org.cn/api/v2/
ENV PYRO_BASE_URL=https://archon.bbsmc.org.cn
ENV SHARED_INSTANCES_API_BASE_URL=https://shared-instances.bbsmc.org.cn

RUN pnpm --filter @modrinth/frontend build

FROM node:24-alpine
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.33.2 --activate

COPY --from=builder /app/apps/frontend/.output ./.output
COPY --from=builder /app/apps/frontend/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules

EXPOSE 3000
ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000
ENV BASE_URL=https://bbsmc.org.cn/api/v2/
ENV BROWSER_BASE_URL=https://bbsmc.org.cn/api/v2/
ENV PYRO_BASE_URL=https://archon.bbsmc.org.cn
ENV SHARED_INSTANCES_API_BASE_URL=https://shared-instances.bbsmc.org.cn

CMD ["node", ".output/server/index.mjs"]
