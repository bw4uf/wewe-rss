FROM node:20.16.0-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN npm i -g pnpm

FROM base AS build
COPY . /usr/src/app
WORKDIR /usr/src/app

# Install all dependencies including devDependencies for build
# CRITICAL: Use --production=false to ensure devDependencies are installed
# This is needed for CLI tools like @nestjs/cli, typescript, vite, etc.
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile --production=false

# ULTIMATE CACHE BUSTER - FORCE COMPLETE REBUILD
ENV FORCE_REBUILD=20250127_v4_WORKSPACE_FIX
ENV NO_CACHE=true

# Ensure all workspace dependencies are properly linked after copying all files
# This step is crucial for monorepo setups to ensure each workspace has access to its dependencies
RUN echo "Re-installing workspace dependencies to ensure proper linking..." && \
    pnpm install -r --frozen-lockfile --offline && \
    echo "Workspace dependencies re-linked successfully!"

RUN echo "FORCE REBUILD: $FORCE_REBUILD at $(date)" && \
    echo "Verifying tools availability..." && \
    pnpm --version && \
    which pnpm && \
    echo "PATH: $PATH" && \
    echo "Checking CLI tools in workspaces..." && \
    cd apps/server && pnpm exec which nest && \
    cd ../web && pnpm exec which tsc && pnpm exec which vite && \
    cd ../..

# Now build with properly linked workspace dependencies
# Using updated build scripts that explicitly use pnpm exec
RUN echo "Building all projects with workspace dependencies properly linked..." && \
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