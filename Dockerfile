# ------- 构建阶段 -------
FROM node:20-alpine AS builder
WORKDIR /usr/src/app

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
RUN pnpm run -r build

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
COPY --from=builder /usr/src/app/apps/server/dist ./dist
COPY --from=builder /usr/src/app/apps/server/prisma ./prisma
COPY --from=builder /usr/src/app/apps/server/docker-bootstrap.sh ./docker-bootstrap.sh
COPY --from=builder /usr/src/app/apps/server/index.js ./index.js

# 设置脚本权限
RUN chmod +x ./docker-bootstrap.sh

# 创建兼容性入口文件，包含完整启动逻辑
RUN echo '#!/usr/bin/env node' > ./dist/index.js && \
    echo '// Compatibility entry point for Zeabur' >> ./dist/index.js && \
    echo 'const { execSync } = require("child_process");' >> ./dist/index.js && \
    echo 'const path = require("path");' >> ./dist/index.js && \
    echo 'try {' >> ./dist/index.js && \
    echo '  console.log("🔄 Running database migrations...");' >> ./dist/index.js && \
    echo '  execSync("npx prisma migrate deploy", { stdio: "inherit", env: process.env, cwd: "/app" });' >> ./dist/index.js && \
    echo '  console.log("🚀 Starting application...");' >> ./dist/index.js && \
    echo '  require(path.join(__dirname, "main"));' >> ./dist/index.js && \
    echo '} catch (error) {' >> ./dist/index.js && \
    echo '  console.error("❌ Startup failed:", error.message);' >> ./dist/index.js && \
    echo '  console.error("Error stack:", error.stack);' >> ./dist/index.js && \
    echo '  process.exit(1);' >> ./dist/index.js && \
    echo '}' >> ./dist/index.js && \
    chmod +x ./dist/index.js

# 调试信息：显式打印产物
RUN echo "📁 Contents of /app/dist:" && ls -la /app/dist
RUN echo "📄 Contents of /app/dist/index.js:" && cat /app/dist/index.js
RUN [ -f /app/dist/main.js ] || (echo "❌ main.js not found" && exit 1)
RUN [ -f /app/dist/index.js ] || (echo "❌ index.js not found" && exit 1)
RUN echo "✅ All required files are present"

# 暴露端口
EXPOSE 4000

# 环境变量
ENV NODE_ENV=production
ENV HOST="0.0.0.0"
ENV SERVER_ORIGIN_URL=""
ENV MAX_REQUEST_PER_MINUTE=60
ENV AUTH_CODE=""
ENV DATABASE_URL=""

# 启动命令 - 直接使用 Zeabur 期望的入口文件
CMD ["node", "dist/index.js"]