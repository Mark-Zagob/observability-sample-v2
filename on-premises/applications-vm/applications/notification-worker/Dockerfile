# ============================================
# Stage 1: Build — install dependencies
# ============================================
FROM python:3.12-slim-bookworm AS builder

WORKDIR /build
COPY notification-worker/requirements.txt .
RUN pip install --no-cache-dir --no-compile \
    --prefix=/install -r requirements.txt

# ============================================
# Stage 2: Runtime — production image
# ============================================
FROM python:3.12-slim-bookworm

LABEL maintainer="observability-lab"
LABEL service="notification-worker"

# Security: non-root user
RUN groupadd -r appuser && useradd -r -g appuser -s /usr/sbin/nologin appuser

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Copy ONLY installed packages from builder
COPY --from=builder /install /usr/local

# Copy application code
COPY shared/ ./shared/
COPY notification-worker/app.py .

# Health check
HEALTHCHECK --interval=10s --timeout=3s --retries=3 --start-period=10s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5004/health/live')" || exit 1

USER appuser

EXPOSE 5004
CMD ["gunicorn", "--workers", "1", "--bind", "0.0.0.0:5004", \
     "--access-logfile", "-", "--timeout", "30", \
     "--worker-tmp-dir", "/dev/shm", "app:app"]
