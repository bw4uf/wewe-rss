FROM node:20.16.0-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN npm i -g pnpm

FROM base AS build
COPY . /usr/src/app
WORKDIR /usr/src/app

RUN npm config set registry https://registry.npmmirror.com
RUN pnpm add -g @nestjs/cli typescript vite
RUN echo "PATH=$PATH" && which node && which pnpm && which nest && which tsc && which vite
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --force

# 使用国内镜像并安装构建所需CLI（兜底，避免未解析到本地dev依赖时失败）
RUN npm config set registry https://registry.npmmirror.com && \
    npm i -g @nestjs/cli typescript vite

# 使用显式的根脚本构建，避免递归运行时 PATH 注入差异
RUN pnpm run build:server && pnpm run build:web

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