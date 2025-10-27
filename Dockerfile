# 使用稳定的 Node.js 镜像
FROM node:20-alpine AS base

# 启用 corepack 来管理 pnpm 版本 (Node.js 18+ 通常自带)
RUN corepack enable

FROM base AS build
WORKDIR /app

# 复制包管理文件
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/server/package.json ./apps/server/
COPY apps/web/package.json ./apps/web/

# 根据 package.json 中的 "packageManager" 字段安装指定版本的 pnpm
RUN corepack install

# 安装所有依赖（包括开发依赖）
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile --production=false

# 复制项目源代码
COPY . .

# 再次确保所有工作区（workspace）的依赖都被正确安装和链接
RUN pnpm install -r --frozen-lockfile

# CACHE BUSTER - 确保重新构建
ENV FORCE_REBUILD=20250127_v7_COREPACK_FIX
ENV NO_CACHE=true

# 验证 CLI 工具是否可用
RUN echo "FORCE REBUILD: $FORCE_REBUILD at $(date)" && \
    echo "=== 验证 pnpm 和工作区设置 ===" && \
    pnpm --version && \
    pnpm list -r --depth=0 && \
    echo "=== 验证 CLI 工具安装 ===" && \
    echo "检查根目录 node_modules/.bin:" && \
    ls -la node_modules/.bin/ | grep -E "(nest|tsc|vite)" || echo "根目录未找到CLI工具" && \
    echo "检查 apps/server:" && \
    cd apps/server && \
    ls -la node_modules/.bin/ | grep -E "(nest|tsc)" || echo "server未找到CLI工具" && \
    npx nest -v || echo "npx nest 失败" && \
    echo "检查 apps/web:" && \
    cd ../web && \
    ls -la node_modules/.bin/ | grep -E "(tsc|vite)" || echo "web未找到CLI工具" && \
    npx tsc -v || echo "npx tsc 失败" && \
    npx vite --version || echo "npx vite 失败" && \
    cd ../.. && \
    echo "CLI工具验证完成!"

# Now build with properly installed workspace dependencies
# Using updated build scripts that explicitly use pnpm exec
RUN echo "Building all projects with CLI tools verified..." && \
    pnpm run -r build && \
    echo "Build completed successfully!"

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