FROM python:3.12-slim

# === Metadata ===
LABEL maintainer="observability-lab"
LABEL service="webhook-receiver"

# === Security: non-root user ===
RUN groupadd -r appuser && useradd -r -g appuser appuser

# === Dependencies ===
WORKDIR /app
RUN pip install --no-cache-dir flask==3.1.*

# === Application code ===
COPY app.py .

# === Health check ===
HEALTHCHECK --interval=10s --timeout=3s --retries=3 --start-period=5s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:9095/')" || exit 1

# === Run as non-root ===
USER appuser

EXPOSE 9095
CMD ["python", "app.py"]
