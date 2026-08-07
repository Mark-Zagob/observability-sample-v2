# ADR-019: Migration Orchestration Strategy

## Status

Accepted (Phase 2.1) — Will be superseded in Phase 3+

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
- Phase 3: Migration orchestration moves out of Terraform into CI/CD pipeline
- Phase 7: Migration becomes a Kubernetes-native concern
- All phases share the same `init-app.sql` and `schema_migrations` table
