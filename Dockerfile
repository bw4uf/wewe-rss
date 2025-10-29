# ------- 构建阶段 -------
FROM node:20-alpine AS builder
WORKDIR /usr/src/app

# 配置 npm 镜像源（解决 Zeabur 构建时网络超时问题）
RUN npm config set registry https://registry.npmmirror.com

# 安装 pnpm
RUN npm i -g pnpm

# 拷贝依赖描述文件
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/server/package.json ./apps/server/
COPY apps/web/package.json ./apps/web/

# 安装全部依赖（含 dev）
RUN pnpm install --force

# 拷贝源码 & 构建
COPY . .
RUN pnpm run build:server && pnpm run build:web

# 创建 Zeabur 期望的根目录 dist/index.js
RUN mkdir -p dist && \
    echo 'console.log("🚀 Starting via root dist/index.js...");' > dist/index.js && \
    echo 'const { execSync } = require("child_process");' >> dist/index.js && \
    echo 'try {' >> dist/index.js && \
    echo '  console.log("🔄 Running database migrations...");' >> dist/index.js && \
    echo '  execSync("npx prisma migrate deploy", { stdio: "inherit", env: process.env, cwd: "/app" });' >> dist/index.js && \
    echo '  console.log("🚀 Starting NestJS application...");' >> dist/index.js && \
    echo '  require("./apps/server/dist/main");' >> dist/index.js && \
    echo '} catch (error) {' >> dist/index.js && \
    echo '  console.error("❌ Startup failed:", error.message);' >> dist/index.js && \
    echo '  console.error("Error stack:", error.stack);' >> dist/index.js && \
    echo '  process.exit(1);' >> dist/index.js && \
    echo '}' >> dist/index.js

# ------- 运行阶段 -------
FROM node:20-alpine
WORKDIR /app

# 安装 pnpm
RUN npm i -g pnpm

# 拷贝依赖描述文件 & 安装生产依赖
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/server/package.json ./apps/server/
RUN pnpm install --prod --force

# 拷贝构建产物
COPY --from=builder /usr/src/app/dist ./dist
COPY --from=builder /usr/src/app/apps/server/dist ./apps/server/dist
COPY --from=builder /usr/src/app/apps/server/client ./apps/server/client
COPY --from=builder /usr/src/app/apps/server/prisma ./prisma
COPY --from=builder /usr/src/app/apps/server/docker-bootstrap.sh ./apps/server/docker-bootstrap.sh
COPY --from=builder /usr/src/app/apps/server/index.js ./apps/server/index.js

# 设置脚本权限
RUN chmod +x ./apps/server/docker-bootstrap.sh

# 确保根入口 dist/index.js 存在（Zeabur 会强制执行）
RUN mkdir -p dist && \
    echo 'console.log("🚀 Starting via root dist/index.js...");' > dist/index.js && \
    echo 'const { execSync } = require("child_process");' >> dist/index.js && \
    echo 'try {' >> dist/index.js && \
    echo '  console.log("🔄 Running database migrations...");' >> dist/index.js && \
    echo '  execSync("npx prisma migrate deploy", { stdio: "inherit", env: process.env, cwd: "/app/apps/server" });' >> dist/index.js && \
    echo '  console.log("🚀 Starting NestJS application...");' >> dist/index.js && \
    echo '  require("./apps/server/dist/main");' >> dist/index.js && \
    echo '} catch (error) {' >> dist/index.js && \
    echo '  console.error("❌ Startup failed:", error.message);' >> dist/index.js && \
    echo '  console.error("Error stack:", error.stack);' >> dist/index.js && \
    echo '  process.exit(1);' >> dist/index.js && \
    echo '}' >> dist/index.js


# 暴露端口
EXPOSE 4000

# 环境变量
ENV NODE_ENV=production
ENV HOST="0.0.0.0"
ENV SERVER_ORIGIN_URL=""
ENV MAX_REQUEST_PER_MINUTE=60
ENV AUTH_CODE=""
ENV DATABASE_URL=""

# 保持在根目录运行以兼容平台入口，并加入回退启动逻辑
WORKDIR /app
# 优先执行 /app/dist/index.js；若不存在则回退到 apps/server 启动脚本
ENTRYPOINT ["sh", "-c", "node dist/index.js || (cd apps/server && sh docker-bootstrap.sh)"]