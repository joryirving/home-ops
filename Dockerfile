# ============================================
# OpenClaw Chat - Hardened Container
# ============================================

# Build stage
FROM node:18-alpine AS builder

WORKDIR /build

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Production stage
FROM node:18-alpine AS production

# Security: Create non-root user
RUN addgroup -g 1000 -S appgroup && \
    adduser -u 1000 -S appuser -G appgroup

WORKDIR /app

# Copy package files and install
COPY package*.json ./
RUN npm ci --only=production

# Copy application code
COPY --chown=appuser:appgroup . .

# Switch to non-root user
USER appuser

# Security: Drop capabilities
# Security: Read-only filesystem (runtime option)
# Security: No new privileges

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/api/auth || exit 1

CMD ["node", "server.js"]
