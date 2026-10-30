# syntax=docker/dockerfile:1
# ============================================
# Stage 1: Build — install dependencies
# ============================================
FROM python:3.12-slim-bookworm@sha256:623674a14ef93d052bb9b0de4dbf5f28eb578a35263838941cc8aa43213c1487 AS builder

WORKDIR /build
COPY api-gateway/requirements.txt .
# -------------------------------------------------------
# Anchor: BuildKit Cache Mount — Mount persistent pip cache vào build context.
# 
# Tại sao bỏ --no-cache-dir?
#   --no-cache-dir khiến pip KHÔNG ghi vào cache directory.
#   Khi dùng cache mount, ta muốn pip sử dụng cache để tránh download lại
#   packages từ PyPI khi rebuild layer này (requirements.txt thay đổi).
#
# 📊 Expected improvement:
#   - Cold build (no pip cache): ~30-60s download packages
#   - Warm build (pip cache HIT): ~5-10s (chỉ install, không download)
# -------------------------------------------------------
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-compile \
    --prefix=/install -r requirements.txt

# ============================================
# Stage 2: Runtime — production image
# ============================================
FROM python:3.12-slim-bookworm@sha256:623674a14ef93d052bb9b0de4dbf5f28eb578a35263838941cc8aa43213c1487

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
COPY api-gateway/gunicorn.conf.py .

# Health check
HEALTHCHECK --interval=10s --timeout=3s --retries=3 --start-period=10s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health/live')" || exit 1

USER appuser

EXPOSE 5000
# 🌟 Use config file for consistency and maintainability
CMD ["gunicorn", "-c", "gunicorn.conf.py", "--bind", "0.0.0.0:5000", "--worker-tmp-dir", "/dev/shm", "app:app"]
