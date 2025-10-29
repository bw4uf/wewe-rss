FROM node:20.16.0-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN npm i -g pnpm

FROM base AS build
WORKDIR /usr/src/app

# 先复制清单文件，最大化缓存并确保 workspace 安装识别到子项目
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/server/package.json ./apps/server/
COPY apps/web/package.json ./apps/web/

RUN npm config set registry https://registry.npmmirror.com
RUN echo "PATH=$PATH" && which node && which pnpm
# 使用递归安装以在各子包安装 devDependencies（避免 CLI 未被安装到子包）
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm -r install --frozen-lockfile

# 复制源码
COPY . .

# 使用 pnpm 的 filter exec 在包上下文执行本地 CLI，避免递归 PATH 注入差异
RUN pnpm --filter server exec nest build && \
    pnpm --filter web exec tsc && \
    pnpm --filter web exec vite build

RUN pnpm deploy --filter=server --prod /app
RUN pnpm deploy --filter=server --prod /app-sqlite

RUN cd /app && pnpm exec prisma generate

RUN cd /app-sqlite && \
    rm -rf ./prisma && \
    mv prisma-sqlite prisma && \
    pnpm exec prisma generate

FROM base AS app-sqlite
COPY --from=build /app-sqlite /app

WORKDIR /app

EXPOSE 4000

ENV NODE_ENV=production
ENV HOST="0.0.0.0"
ENV SERVER_ORIGIN_URL=""
ENV MAX_REQUEST_PER_MINUTE=60
ENV AUTH_CODE=""
ENV DATABASE_URL="file:../data/wewe-rss.db"
ENV DATABASE_TYPE="sqlite"

RUN chmod +x ./docker-bootstrap.sh

CMD ["./docker-bootstrap.sh"]


FROM base AS app
COPY --from=build /app /app

WORKDIR /app

EXPOSE 4000

ENV NODE_ENV=production
ENV HOST="0.0.0.0"
ENV SERVER_ORIGIN_URL=""
ENV MAX_REQUEST_PER_MINUTE=60
ENV AUTH_CODE=""
ENV DATABASE_URL=""

RUN chmod +x ./docker-bootstrap.sh

CMD ["./docker-bootstrap.sh"]