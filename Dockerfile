# ──────────────────────────────────────────────────────────────
# Quadratic ▸ root‑level Dockerfile (API‑only, prod ready)
# ──────────────────────────────────────────────────────────────
#
#  👉  Build:  docker build -t quadratic-api:$(git rev-parse --short HEAD) .
#  👉  Run :   docker run -p 8080:8080 --env-file .env.prod quadratic-api:latest
#
#  Notes
#  ──────────────────────────────────────────────────────────────
#  • Targets the `quadratic-api` workspace only.
#  • Relies on npm workspaces declared in the repo root.
#  • Exposes port 8080 (Quadratic‑API default).
#  • All config comes from environment variables injected by
#    DigitalOcean App Platform.
#  • Add other services (files, multiplayer, connection) later
#    as separate components or images.
# ──────────────────────────────────────────────────────────────

###############################
# Stage 1 — Build / Compile   #
###############################
FROM node:20-alpine AS builder

# Install packages needed for native modules (sqlite3, etc.)
RUN apk add --no-cache --virtual .build-deps \
      python3 make g++ git

WORKDIR /src

# 1. Copy only the files that affect dependency graph first
COPY package*.json ./
COPY .npmrc* ./

# 2. Install all workspace deps (root + packages)
RUN npm ci --ignore-scripts

# 3. Copy the full source tree
COPY . .

# 4. Build just the API workspace (typescript → dist)
RUN npm run build --workspace=quadratic-api

#################################
# Stage 2 — Runtime (thin)      #
#################################
FROM node:20-alpine

# Minimal runtime utilities
RUN apk add --no-cache dumb-init

WORKDIR /app

# Metadata (helpful in DO console)
ARG VCS_REF
ARG BUILD_DATE
LABEL org.opencontainers.image.title="Quadratic API" \
      org.opencontainers.image.description="Quadratic backend (monorepo build)" \
      org.opencontainers.image.version="${VCS_REF}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/bhctest123/quadratic"

# Copy compiled output & package manifests
COPY --from=builder /src/quadratic-api/dist ./dist
COPY --from=builder /src/quadratic-api/package*.json ./

# Install prod‑only deps for the API workspace
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force

# Environment hygiene
ENV NODE_ENV=production \
    PORT=8080

EXPOSE 8080

# Healthcheck (optional — uncomment if desired)
# HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://localhost:8080/health || exit 1

# Use dumb-init for proper signal handling
ENTRYPOINT ["dumb-init", "--"]

# Start the server
CMD ["node", "dist/src/server.js"]
