# ADR-019: Migration Orchestration Strategy

## Status

Accepted (Phase 2.1) — Will be superseded in Phase 3+

> **Updated**: Added SSM Gate pattern (cross-state deployment blocking)
> and DDL/DML privilege separation (app_user).

## Context

Database schema migrations must run before application deployment. The orchestration
mechanism needs to:

1. Block app deployment if migration fails
2. Be idempotent (safe to re-run)
3. Provide audit trail (CloudWatch Logs)
4. Support progressive complexity as the project evolves

## Decision

### Phase 2.1 (Current): `null_resource` + `local-exec`

```hcl
resource "null_resource" "run_migration" {
  provisioner "local-exec" {
    command = "aws ecs run-task ... && aws ecs wait tasks-stopped ..."
  }
}
```

**Trade-offs:**
- ✅ Simple, fast iteration
- ✅ Migration task itself is idempotent
- ❌ Requires AWS CLI on developer laptop
- ❌ No retry at Terraform level (task-level retry is in run-migration.sh)
- ❌ `terraform plan` cannot preview migration changes

### Cross-State Coordination: SSM Gate

Control Plane and Data Plane are separate Terraform states.
`depends_on` cannot cross state boundaries. Solution: SSM parameters as a
machine-readable contract.

```
Control Plane (migration)  ──writes──▸  /obs/lab/migration/status = SUCCESS|FAILED
Data Plane   (order-service) ──reads──▸  check "migration_gate" { assert ... }
```

- Migration success → writes `status=SUCCESS`, `schema_version`, `last_success`
- Migration failure → writes `status=FAILED` (best-effort, `|| true`)
- Data Plane `check` block validates gate before deploy

### DDL/DML Privilege Separation

Migration task uses **master user** (DDL: CREATE/ALTER/GRANT).
App runtime uses **app_user** (DML-only: SELECT/INSERT/UPDATE/DELETE).

- `app_user` secret created by database module (`app_user.tf`)
- `init-app.sql` provisions the role via `\gexec` (idempotent)
- Verification: `has_schema_privilege('app_user', 'public', 'CREATE')` must be `false`

### Phase 3 (CI/CD): GitHub Actions Step

```yaml
# .github/workflows/deploy.yml
- name: Run Database Migration
  uses: aws-actions/amazon-ecs-run-task@v1
  with:
    task-definition: migration
    cluster: obs-cluster
    wait-for-finish: true
    wait-for-minutes: 10
```

**Why better:**
- OIDC authentication (no long-lived credentials)
- Built-in retry and timeout
- Pipeline visibility and approval gates

### Phase 7 (EKS): ArgoCD PreSync Hook

```yaml
# k8s/migration-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
```

**Why better:**
- GitOps-native (declarative, auditable)
- Automatic rollback on failure
- Kubernetes Job retry semantics

## Consequences

- Phase 2.1: Acceptable tech debt — documented in `bootstrap-migration/main.tf`
- Phase 2.1: SSM Gate pattern provides cross-state deployment safety
- Phase 2.1: DDL/DML separation enforced at SQL level (not just IAM)
- Phase 3: Migration orchestration moves out of Terraform into CI/CD pipeline
- Phase 7: Migration becomes a Kubernetes-native concern
- All phases share the same `init-app.sql` and `schema_migrations` table

## References

- Runbook: `docs/RUNBOOK_migration_deploy.md`
- Migration SQL: `migration/init-app.sql`
- Bootstrap module: `modules/bootstrap-migration/`
