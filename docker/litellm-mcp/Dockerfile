# syntax=docker/dockerfile:1
FROM --platform=linux/amd64 node:24.21.0-bookworm-slim@sha256:d6aa754f16b3197301076f047b5def2f02ea1dbbc2ca920407d46d7ec7f87b20 AS npm-deps
WORKDIR /build
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund

FROM ghcr.io/berriai/litellm-database:v1.104.0@sha256:fbe28229d2d02181c0a7d9df9599de614b491f3d897d2d7da18404f088310218

USER root

# Use the exact Node executable and GitHub MCP server from their source OCI images.
COPY --from=node:24.21.0-bookworm-slim@sha256:d6aa754f16b3197301076f047b5def2f02ea1dbbc2ca920407d46d7ec7f87b20 /usr/local/bin/node /usr/local/bin/node
COPY --from=ghcr.io/github/github-mcp-server:2.0.1@sha256:03f565ea952662cd14a8a0373d910aeced3aff7197ab6afef786755db8d25994 /server/github-mcp-server /opt/mcp/bin/github-mcp-server
COPY --from=npm-deps /build/node_modules /opt/mcp/node_modules
COPY launch.py /opt/mcp/launch.py

# Dispatch's published image is an npm-free runtime image. Extract its preinstalled,
# tested executable, application files, and pruned production dependencies by digest.
COPY --from=ghcr.io/misospace/dispatch-mcp:sha-e4eaba8@sha256:11fee95712142758e1ff4c608ff0c7104ab391926fec5f96e8ea6ec63a8b1bed /app/node_modules /opt/mcp/dispatch/node_modules
COPY --from=ghcr.io/misospace/dispatch-mcp:sha-e4eaba8@sha256:11fee95712142758e1ff4c608ff0c7104ab391926fec5f96e8ea6ec63a8b1bed /app/src/mcp /opt/mcp/dispatch/src/mcp
COPY --from=ghcr.io/misospace/dispatch-mcp:sha-e4eaba8@sha256:11fee95712142758e1ff4c608ff0c7104ab391926fec5f96e8ea6ec63a8b1bed /app/src/lib /opt/mcp/dispatch/src/lib
COPY --from=ghcr.io/misospace/dispatch-mcp:sha-e4eaba8@sha256:11fee95712142758e1ff4c608ff0c7104ab391926fec5f96e8ea6ec63a8b1bed /app/package.json /opt/mcp/dispatch/package.json

RUN mkdir -p /home/nonroot /tmp /var/run/litellm-mcp/arr /var/run/litellm-mcp/seerr /var/run/litellm-mcp/github /var/run/litellm-mcp/dispatch \
    && chown -R 1000:1000 /home/nonroot /tmp \
    && chmod 0555 /var/run/litellm-mcp /var/run/litellm-mcp/arr /var/run/litellm-mcp/seerr /var/run/litellm-mcp/github /var/run/litellm-mcp/dispatch \
    && chmod 0555 /opt/mcp/bin/github-mcp-server \
    && chmod 0555 /opt/mcp/launch.py

ENV HOME=/home/nonroot \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/app/.venv/bin


USER 1000:1000
