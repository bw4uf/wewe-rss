FROM node:20.16.0-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN npm i -g pnpm

FROM base AS build
COPY . /usr/src/app
WORKDIR /usr/src/app

# Install all dependencies including devDependencies for build
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile

# FORCE CACHE INVALIDATION - DO NOT USE OLD CACHED LAYERS
ENV CACHE_BUST=20250127_v2
RUN echo "Force rebuild - Cache bust: $CACHE_BUST - $(date)" > /tmp/build-info
RUN echo "Verifying pnpm and tools..." && pnpm --version && which pnpm

# Build projects using pnpm exec to ensure CLI tools are in PATH
# IMPORTANT: These commands replace the old 'pnpm run -r build'
RUN echo "Building server..." && cd apps/server && pnpm exec nest build
RUN echo "Building web..." && cd apps/web && pnpm exec tsc && pnpm exec vite build

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