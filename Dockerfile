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
RUN pnpm install --frozen-lockfile

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
RUN pnpm install --prod --frozen-lockfile

# 拷贝构建产物
COPY --from=builder /usr/src/app/apps/server/dist ./dist
COPY --from=builder /usr/src/app/apps/server/prisma ./prisma
COPY --from=builder /usr/src/app/apps/server/docker-bootstrap.sh ./docker-bootstrap.sh

# 设置脚本权限
RUN chmod +x ./docker-bootstrap.sh

# 暴露端口
EXPOSE 4000

# 环境变量
ENV NODE_ENV=production
ENV HOST="0.0.0.0"
ENV SERVER_ORIGIN_URL=""
ENV MAX_REQUEST_PER_MINUTE=60
ENV AUTH_CODE=""
ENV DATABASE_URL=""

# 启动命令
CMD ["./docker-bootstrap.sh"]