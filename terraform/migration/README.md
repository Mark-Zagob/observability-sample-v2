# Database Migration — Bootstrap Task

## Overview

Production-grade database schema bootstrapping using a dedicated ECS Fargate task. Implements the **Migration Plane** pattern: `Control Plane → Migration Plane → Data Plane`.

## Architecture

```
┌─ Control Plane (Terraform) ─────────────────────────┐
│  RDS provisioned → Secret created → Task def ready   │
└───────────────────────┬─────────────────────────────┘
                        ▼
┌─ Migration Plane (ECS RunTask) ─────────────────────┐
│  Read secret → Connect RDS → Run init-app.sql        │
│  Exit 0 (success) or Exit 1 (fail → block deploy)   │
└───────────────────────┬─────────────────────────────┘
                        ▼
┌─ Data Plane (App Services) ─────────────────────────┐
│  Order/Payment connect with DML-only privileges      │
└─────────────────────────────────────────────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Migration container (postgres:16-alpine + AWS CLI) |
| `run-migration.sh` | Entrypoint: secret read → RDS wait → psql → verify |
| `init-app.sql` | Idempotent DDL + seed data with advisory lock |

## Usage

### 1. Build & Push Image

```bash
# From terraform/migration/
aws ecr get-login-password --region ap-southeast-2 | docker login --username AWS --password-stdin <account>.dkr.ecr.ap-southeast-2.amazonaws.com

docker build -t migration:v1 .
docker tag migration:v1 <account>.dkr.ecr.ap-southeast-2.amazonaws.com/migration:v1
docker push <account>.dkr.ecr.ap-southeast-2.amazonaws.com/migration:v1
```

### 2. Terraform Apply

The `bootstrap-migration` module in `control-plane/lab/main.tf` automatically runs the task on `terraform apply`.

### 3. Verify

```bash
# Check CloudWatch Logs
aws logs tail /ecs/obs/lab/migration --follow --region ap-southeast-2
```

## IAM Separation

| Role | Privileges | Used By |
|------|-----------|---------|
| Migration Role | `secretsmanager:GetSecretValue`, `kms:Decrypt` | Migration task (DDL) |
| App Task Role | `secretsmanager:GetSecretValue`, `kms:Decrypt` | Order/Payment (DML only) |

The DDL vs DML separation is enforced at the PostgreSQL level — the migration task connects as the master user (DDL), while app services should connect as a restricted user (DML only) in production.

## Idempotency

All SQL statements are idempotent:
- `CREATE TABLE IF NOT EXISTS` — safe to re-run
- `CREATE INDEX IF NOT EXISTS` — safe to re-run
- `INSERT ... ON CONFLICT DO NOTHING` — safe to re-run
- `pg_advisory_lock()` — prevents concurrent DDL
