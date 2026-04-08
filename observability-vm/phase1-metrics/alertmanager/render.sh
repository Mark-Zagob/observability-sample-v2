#!/bin/bash
# Render alertmanager.yml từ template + .env
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
# Load .env
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "❌ File .env không tồn tại! Copy từ .env.example:"
    echo "   cp .env.example .env"
    exit 1
fi
# Render template → file thật
envsubst < "$SCRIPT_DIR/alertmanager.yml.tpl" > "$SCRIPT_DIR/alertmanager.yml"
echo "✅ Rendered alertmanager.yml (secrets injected from .env)"
