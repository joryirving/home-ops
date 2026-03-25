FROM python:3.12-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY proxy.py data_proxy.py mcp_server.py optimizer.py test_all.py .

# Expose port
EXPOSE 8080

# Run the proxy server
CMD ["python3", "proxy.py"]
