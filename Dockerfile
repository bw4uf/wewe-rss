FROM node:20.16.0-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN npm i -g pnpm

FROM base AS build
WORKDIR /usr/src/app

# First, copy package files for dependency installation
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/server/package.json ./apps/server/
COPY apps/web/package.json ./apps/web/

# Install all dependencies including devDependencies for build
# CRITICAL: Use --production=false to ensure devDependencies are installed
# This is needed for CLI tools like @nestjs/cli, typescript, vite, etc.
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile --production=false

# ULTIMATE CACHE BUSTER - FORCE COMPLETE REBUILD
ENV FORCE_REBUILD=20250127_v6_GLOBAL_INSTALL
ENV NO_CACHE=true

# Install global build tools as backup (方案二)
RUN pnpm add -g @nestjs/cli typescript

# Now copy the rest of the source code
COPY . .

# Re-install workspace dependencies to ensure proper linking (关键步骤)
RUN echo "Re-installing workspace dependencies..." && \
    pnpm install -r --frozen-lockfile && \
    echo "Workspace dependencies re-installed successfully!"

# Verify CLI tools are available in each workspace BEFORE building
RUN echo "FORCE REBUILD: $FORCE_REBUILD at $(date)" && \
    echo "Verifying tools availability..." && \
    pnpm --version && \
    which pnpm && \
    echo "PATH: $PATH" && \
    echo "=== Global CLI tools ===" && \
    which nest && which tsc && \
    echo "=== Checking apps/server ===" && \
    cd apps/server && \
    ls -la node_modules/.bin/ | head -10 && \
    pnpm exec which nest || echo "nest not found in workspace, using global" && \
    echo "=== Checking apps/web ===" && \
    cd ../web && \
    ls -la node_modules/.bin/ | head -10 && \
    pnpm exec which tsc || echo "tsc not found in workspace, using global" && \
    pnpm exec which vite || echo "vite not found in workspace, using global" && \
    cd ../.. && \
    echo "All CLI tools verified successfully!"

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