# syntax=docker/dockerfile:1
# ============================================
# Stage 1: Build — install dependencies
# ============================================
FROM python:3.12-slim-bookworm@sha256:623674a14ef93d052bb9b0de4dbf5f28eb578a35263838941cc8aa43213c1487 AS builder

WORKDIR /build
COPY inventory-worker/requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-compile \
    --prefix=/install -r requirements.txt

# ============================================
# Stage 2: Runtime — production image
# ============================================
FROM python:3.12-slim-bookworm@sha256:623674a14ef93d052bb9b0de4dbf5f28eb578a35263838941cc8aa43213c1487

LABEL maintainer="observability-lab"
LABEL service="inventory-worker"

# Security: non-root user
RUN groupadd -r appuser && useradd -r -g appuser -s /usr/sbin/nologin appuser

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Copy ONLY installed packages from builder
COPY --from=builder /install /usr/local

# Copy application code
COPY shared/ ./shared/
COPY inventory-worker/app.py .
COPY inventory-worker/gunicorn.conf.py .

# Health check
HEALTHCHECK --interval=10s --timeout=3s --retries=3 --start-period=10s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5005/health/live')" || exit 1

USER appuser

EXPOSE 5005
# 🌟 Use config file for consistency and maintainability
CMD ["gunicorn", "-c", "gunicorn.conf.py", "--bind", "0.0.0.0:5005", "--worker-tmp-dir", "/dev/shm", "app:app"]
