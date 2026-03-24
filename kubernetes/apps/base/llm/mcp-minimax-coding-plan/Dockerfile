FROM python:3.11-slim

RUN pip install uv

WORKDIR /app

# Run via uvx with SSE transport for network accessibility
CMD ["uvx", "minimax-coding-plan-mcp", "--transport", "sse"]
