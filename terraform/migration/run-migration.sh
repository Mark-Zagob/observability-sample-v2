#!/bin/bash
# terraform/migration/run-migration.sh
# ============================================================
# Database Migration Runner — Production-Grade
# ============================================================
# Responsibilities:
#   1. Validate environment variables
#   2. Read credentials from AWS Secrets Manager
#   3. Wait for RDS readiness
#   4. Execute migration SQL (via psql)
#   5. Cleanup sensitive data
#
# Verification logic lives ENTIRELY in init-app.sql (Single Source of Truth)
# ============================================================

set -euo pipefail

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

log "🚀 Starting database migration..."
log "   DB_HOST=${DB_HOST:-<not set>}"
log "   DB_NAME=${DB_NAME:-<not set>}"
log "   AWS_REGION=${AWS_REGION:-ap-southeast-2}"

# --- Validate required environment variables ---
for var in DB_SECRET_ARN DB_HOST DB_NAME APP_USER_SECRET_ARN; do
  if [ -z "${!var:-}" ]; then
    log "❌ Required variable $var is not set"
    exit 1
  fi
done

# --- Read credentials from Secrets Manager ---
log "📖 Reading database credentials from Secrets Manager..."
DB_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$DB_SECRET_ARN" \
  --query SecretString --output text \
  --region "${AWS_REGION:-ap-southeast-2}") || {
    log "❌ Failed to read secret from Secrets Manager"
    exit 1
  }

DB_USER=$(echo "$DB_SECRET" | jq -r '.username // empty')
DB_PASS=$(echo "$DB_SECRET" | jq -r '.password // empty')

if [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
  log "❌ Failed to parse database credentials (username or password empty)"
  exit 1
fi

log "✅ Master credentials loaded for user: $DB_USER"

# --- Read app-user secret (to provision DML-only role) ---
log "📖 Reading app-user credentials from Secrets Manager..."
APP_USER_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$APP_USER_SECRET_ARN" \
  --query SecretString --output text \
  --region "${AWS_REGION:-ap-southeast-2}") || {
    log "❌ Failed to read app-user secret"
    exit 1
  }

APP_USER_PASS=$(echo "$APP_USER_SECRET" | jq -r '.password // empty')
if [ -z "$APP_USER_PASS" ]; then
  log "❌ App-user secret missing 'password' field"
  exit 1
fi
log "✅ App-user credentials loaded"

# --- Wait for RDS readiness (max 5 minutes) ---
log "⏳ Waiting for RDS to accept connections..."
RETRIES=30
until pg_isready -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1; do
  RETRIES=$((RETRIES - 1))
  if [ $RETRIES -le 0 ]; then
    log "❌ RDS not ready after 5 minutes — aborting"
    exit 1
  fi
  log "   Not ready, retrying in 10s... ($RETRIES retries left)"
  sleep 10
done
log "✅ RDS is accepting connections"

# --- Run migration ---
# Statement Timeout: 120s (migration) vs 30s (app runtime in shared/db_utils.py)
# Migration is one-shot DDL — CREATE INDEX can be slow on large tables.
# App is long-running DML — 30s prevents runaway queries from exhausting pool.
log "🗄️  Executing migration scripts..."
export PGPASSWORD="$DB_PASS"
export PGSSLMODE="require"

psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" \
  --set ON_ERROR_STOP=1 \
  --set statement_timeout=120000 \
  -v app_password="$APP_USER_PASS" \
  -f /migrations/init-app.sql 2>&1 || {
    log "❌ Migration SQL failed or verification exception raised — check output above"
    unset PGPASSWORD PGSSLMODE APP_USER_PASS
    exit 1
  }

# Cleanup sensitive data from environment
unset PGPASSWORD PGSSLMODE APP_USER_PASS

# 🌟 Single Source of Truth: Verify logic đã chạy trong init-app.sql
# Nếu psql xuống đến đây = exit code 0 = migration + verify THÀNH CÔNG
log "✅ Migration completed and verified successfully via SQL block."
exit 0