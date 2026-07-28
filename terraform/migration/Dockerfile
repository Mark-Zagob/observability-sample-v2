# terraform/migration/Dockerfile
# ============================================================
# Database Migration Task — Phase 2.1
# ============================================================
# Purpose: One-shot ECS Fargate task to bootstrap RDS schema
# Pattern: Dedicated Migration Plane (Control → Migration → Data)
# ============================================================

FROM postgres:16-alpine

# Install AWS CLI + jq for Secrets Manager integration
RUN apk add --no-cache aws-cli jq bash

# Copy migration artifacts
COPY init-app.sql /migrations/
COPY run-migration.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/run-migration.sh

# Non-root user (production security requirement)
RUN adduser -D -u 1000 migrator
USER migrator

ENTRYPOINT ["/usr/local/bin/run-migration.sh"]
