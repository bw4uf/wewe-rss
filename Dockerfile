FROM node:20.16.0-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN npm i -g pnpm

FROM base AS build
COPY . /usr/src/app
WORKDIR /usr/src/app

# Install all dependencies including devDependencies for build
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile

# ULTIMATE CACHE BUSTER - FORCE COMPLETE REBUILD
ENV FORCE_REBUILD=20250127_v3_FINAL
ENV NO_CACHE=true
RUN echo "FORCE REBUILD: $FORCE_REBUILD at $(date)" && \
    echo "Verifying tools..." && \
    pnpm --version && \
    which pnpm && \
    echo "PATH: $PATH"

# COMPLETELY NEW BUILD APPROACH - NO MORE pnpm run -r build
# Build each project individually with explicit commands
RUN echo "=== BUILDING SERVER APPLICATION ===" && \
    cd apps/server && \
    echo "Current directory: $(pwd)" && \
    echo "Available scripts:" && \
    cat package.json | grep -A 10 '"scripts"' && \
    pnpm exec nest build && \
    echo "Server build completed, checking output:" && \
    ls -la dist/

RUN echo "=== BUILDING WEB APPLICATION ===" && \
    cd apps/web && \
    echo "Current directory: $(pwd)" && \
    echo "Available scripts:" && \
    cat package.json | grep -A 10 '"scripts"' && \
    pnpm exec tsc && \
    pnpm exec vite build && \
    echo "Web build completed, checking output:" && \
    ls -la ../server/client/

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