#!/bin/bash
# terraform/migration/run-migration.sh
# ============================================================
# Database Migration Runner — Production-Grade
# ============================================================
# Features:
#   - Reads credentials from AWS Secrets Manager (no hardcoded passwords)
#   - Waits for RDS readiness with retry (handles cold start / failover)
#   - Runs idempotent SQL migration
#   - Verifies migration success before exit
#   - All output goes to CloudWatch Logs via ECS awslogs driver
# ============================================================

set -euo pipefail

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

log "🚀 Starting database migration..."
log "   DB_HOST=${DB_HOST:-<not set>}"
log "   DB_NAME=${DB_NAME:-<not set>}"
log "   AWS_REGION=${AWS_REGION:-<not set>}"

# --- Validate required environment variables ---
for var in DB_SECRET_ARN DB_HOST DB_NAME; do
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

log "✅ Credentials loaded for user: $DB_USER"

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
log "🗄️  Executing migration scripts..."
export PGPASSWORD="$DB_PASS"
export PGSSLMODE="require"  # RDS has rds.force_ssl=1 — fail-fast if TLS broken

psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" \
  --set ON_ERROR_STOP=1 \
  -f /migrations/init-app.sql 2>&1 || {
    log "❌ Migration SQL failed — check output above"
    unset PGPASSWORD
    exit 1
  }

# --- Verify migration ---
log "🔍 Verifying migration results..."
TABLE_COUNT=$(psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -tAc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';")

PRODUCT_COUNT=$(psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -tAc \
  "SELECT count(*) FROM products;")

SCHEMA_VERSION=$(psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -tAc \
  "SELECT version FROM schema_migrations ORDER BY applied_at DESC LIMIT 1;")

# Cleanup sensitive data from environment
unset PGPASSWORD
unset PGSSLMODE

# Expect exactly 6 tables: orders, products, processed_events, notifications, inventory_log, schema_migrations
if [ "${TABLE_COUNT:-0}" -ne 6 ]; then
  log "❌ Verification failed: expected 6 tables, got ${TABLE_COUNT:-0}"
  exit 1
fi

# Exact count: detect duplicates from non-idempotent seed runs
if [ "${PRODUCT_COUNT:-0}" -ne 5 ]; then
  log "❌ Verification failed: expected exactly 5 seed products, got ${PRODUCT_COUNT:-0}"
  exit 1
fi

log "✅ Migration completed successfully"
log "   Tables: $TABLE_COUNT"
log "   Products: $PRODUCT_COUNT"
log "   Schema version: ${SCHEMA_VERSION:-unknown}"
exit 0
