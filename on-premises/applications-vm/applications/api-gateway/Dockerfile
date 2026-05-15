# ============================================
# Stage 1: Build — install dependencies
# ============================================
FROM python:3.12-slim-bookworm AS builder

WORKDIR /build
COPY api-gateway/requirements.txt .
RUN pip install --no-cache-dir --no-compile \
    --prefix=/install -r requirements.txt

# ============================================
# Stage 2: Runtime — production image
# ============================================
FROM python:3.12-slim-bookworm

LABEL maintainer="observability-lab"
LABEL service="api-gateway"

# Security: non-root user
RUN groupadd -r appuser && useradd -r -g appuser -s /usr/sbin/nologin appuser

# Don't generate .pyc files (saves space + works with read-only fs)
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Copy ONLY installed packages from builder (no pip/setuptools/wheel)
COPY --from=builder /install /usr/local

# Copy application code
COPY shared/ ./shared/
COPY api-gateway/app.py .

# Health check
HEALTHCHECK --interval=10s --timeout=3s --retries=3 --start-period=10s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health/live')" || exit 1

USER appuser

EXPOSE 5000
CMD ["gunicorn", "--workers", "4", "--bind", "0.0.0.0:5000", \
     "--access-logfile", "-", "--timeout", "30", \
     "--worker-tmp-dir", "/dev/shm", "app:app"]
