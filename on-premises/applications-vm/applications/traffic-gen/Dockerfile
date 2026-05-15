# ============================================
# Stage 1: Build — install dependencies
# ============================================
FROM python:3.12-slim-bookworm AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --no-compile \
    --prefix=/install -r requirements.txt

# ============================================
# Stage 2: Runtime — production image
# ============================================
FROM python:3.12-slim-bookworm

LABEL maintainer="observability-lab"
LABEL service="traffic-gen"

# Security: non-root user
RUN groupadd -r appuser && useradd -r -g appuser -s /usr/sbin/nologin appuser

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Copy ONLY installed packages from builder
COPY --from=builder /install /usr/local

# Copy application code
COPY app.py .

# Health check
HEALTHCHECK --interval=10s --timeout=3s --retries=3 --start-period=5s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5003/health')" || exit 1

USER appuser

EXPOSE 5003
CMD ["python", "app.py"]
