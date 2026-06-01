################################################################################
# Multi-stage Dockerfile for FastAPI + gRPC Microservice
# Stage 1: Builder - install dependencies
# Stage 2: Runtime - minimal production image
#
# Ports:
#   8000  - FastAPI REST API (external/client-facing)
#   50051 - gRPC server (internal service-to-service)
################################################################################

# ── Builder Stage ────────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Runtime Stage ────────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

# Security: Run as non-root user
RUN groupadd -r appuser && useradd -r -g appuser -d /app -s /sbin/nologin appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application code and generated gRPC stubs
COPY src/ ./src/

# Set ownership
RUN chown -R appuser:appuser /app

USER appuser

# Environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000 \
    GRPC_PORT=50051

EXPOSE 8000 50051

# Health check (FastAPI)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/healthz')" || exit 1

# Run with uvicorn (gRPC server starts inside the FastAPI lifespan)
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--access-log"]
