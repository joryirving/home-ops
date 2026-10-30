# syntax=docker/dockerfile:1
# One source for both legacy Courier executor and native Courier harness.
# The caller must pass a reviewed Courier 0.1.12 base image.
ARG COURIER_BASE=ghcr.io/misospace/courier-opencode:0.1.12
FROM ${COURIER_BASE}

COPY --chown=65532:65532 kubernetes/apps/base/llm/opencode/skills/simple-english/ /home/courier/.agents/skills/simple-english/
