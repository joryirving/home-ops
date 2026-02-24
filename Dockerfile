# Stage 1: Build
FROM node:18-alpine AS builder
WORKDIR /build
COPY package*.json ./
RUN npm ci --only=production

# Stage 2: Production
FROM node:18-alpine
RUN addgroup -g 1000 -S appgroup && adduser -u 1000 -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /build/node_modules ./node_modules
COPY package*.json ./
COPY --chown=appuser:appgroup . .
USER appuser
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 CMD wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1
CMD ["node", "server.js"]
