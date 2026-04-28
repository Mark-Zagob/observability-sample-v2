# AWS Architecture — Observability Lab

## 1. Production-Grade Architecture (Target)

```mermaid
graph TB
    subgraph INTERNET["☁️ Internet"]
        USER["👤 Users / Dev"]
        GHA["⚙️ GitHub Actions"]
    end

    subgraph AWS["AWS — ap-southeast-2"]

        subgraph EDGE["Edge + Security Layer"]
            R53["Route53<br/>*.bd-apa-coi.com"]
            ACM["ACM Certificate<br/>Wildcard TLS"]
            WAF["WAF v2<br/>Managed Rules + Rate Limit"]
        end

        subgraph VPC["VPC 10.0.0.0/16"]

            subgraph PUB["Public Subnets × 3 AZs"]
                ALB["ALB<br/>Internet-facing"]
                NAT["NAT Gateway<br/>Per-AZ (HA)"]
                BAST["Bastion Host<br/>SSM Session Manager"]
            end

            subgraph PRIV["Private Subnets × 3 AZs"]
                COMPUTE["🔄 Compute Layer<br/>(swappable 4 phases)"]
                R53_PVT["Route53<br/>Private Hosted Zone<br/>internal.bd-apa-coi.com"]
            end

            subgraph DATA_SUB["Data Subnets × 3 AZs"]
                RDS["RDS PostgreSQL<br/>Multi-AZ + 7d Backup"]
                REDIS["ElastiCache Redis<br/>Replication Group<br/>Auto Failover"]
                MSK["MSK Kafka<br/>TLS + KMS Encryption"]
                EFS["EFS<br/>Encrypted (CMK)"]
            end

        end

        subgraph SUPPORT["Supporting Services"]
            ECR["ECR<br/>7 repos"]
            SM["Secrets Manager<br/>Auto Rotation"]
            SSM["SSM Parameters"]
            CW["CloudWatch<br/>Logs / Metrics / Insights"]
            OIDC["OIDC Provider<br/>GitHub Actions IAM"]
            KMS["KMS CMK<br/>Data Encryption"]
            BUDGET["AWS Budgets<br/>+ Cost Anomaly"]
        end

        subgraph STATE["Terraform State"]
            S3["S3 Backend<br/>Encrypted"]
            DDB["DynamoDB<br/>State Locking"]
        end

    end

    USER -->|"HTTPS"| R53
    R53 --> WAF
    WAF -->|"filtered"| ALB
    ACM -.->|"TLS cert"| ALB
    ALB -->|"forward"| COMPUTE
    COMPUTE -->|"db.internal..."| R53_PVT
    R53_PVT --> RDS & REDIS & MSK
    COMPUTE -.->|"NFS mount"| EFS
    COMPUTE -->|"logs/metrics"| CW
    GHA -->|"OIDC"| OIDC
    OIDC -.->|"push"| ECR
    COMPUTE -.->|"pull"| ECR
    COMPUTE -.->|"read config"| SSM
    COMPUTE -.->|"read secrets"| SM
    KMS -.->|"encrypt"| RDS & REDIS & MSK & EFS & S3
    BAST -.->|"debug"| DATA_SUB
    NAT -->|"outbound"| INTERNET

    style EDGE fill:#1b3a4b,stroke:#2a6f97,color:#fff
    style STATE fill:#2d2d2d,stroke:#666,color:#fff
```

---

## 2. Swappable Compute Layer — 4 Phases

```mermaid
graph LR
    subgraph SHARED["Shared Infrastructure (deploy 1 lần)"]
        NET["Network"]
        SEC["Security"]
        DAT["Data"]
        LB["Load Balancer"]
        SEC2["Secrets"]
        REG["ECR"]
        FS["EFS"]
        BAS["Bastion"]
        CI["CI/CD OIDC"]
    end

    NET --> SEC --> DAT --> LB --> SEC2 --> REG --> FS --> BAS --> CI

    CI --> P8A & P8B & P8C & P8D

    subgraph P8A["Phase 8A: ECS on EC2"]
        direction TB
        A1["ECS Cluster"]
        A2["ASG t3.medium × 2-4"]
        A3["Capacity Provider"]
        A4["Cloud Map SD"]
        A1 --- A2 --- A3 --- A4
    end

    subgraph P8B["Phase 8B: ECS on Fargate"]
        direction TB
        B1["ECS Cluster"]
        B2["Fargate Tasks"]
        B3["Target Tracking Scaling"]
        B4["EFS Volumes"]
        B1 --- B2 --- B3 --- B4
    end

    subgraph P8C["Phase 8C: EKS + Node Group"]
        direction TB
        C1["EKS Control Plane"]
        C2["Managed Node Group × 2-4"]
        C3["Helm Charts"]
        C4["LB Controller + Cluster Autoscaler"]
        C1 --- C2 --- C3 --- C4
    end

    subgraph P8D["Phase 8D: EKS + Fargate"]
        direction TB
        D1["EKS Control Plane"]
        D2["Fargate Profile: apps"]
        D3["Node Group: observability"]
        D4["CoreDNS patched"]
        D1 --- D2 --- D3 --- D4
    end

    style P8A fill:#1a472a,stroke:#2d6a4f,color:#fff
    style P8B fill:#1b3a4b,stroke:#2a6f97,color:#fff
    style P8C fill:#4a1942,stroke:#7b2d8e,color:#fff
    style P8D fill:#5c2a0a,stroke:#b85c1e,color:#fff
```

---

## 3. Network Topology — 3 AZs × 3 Tiers

```mermaid
graph TB
    IGW["Internet Gateway"]

    subgraph VPC["VPC 10.0.0.0/16"]

        subgraph AZ_A["AZ-a"]
            PUB_A["Public<br/>10.0.1.0/24"]
            PRIV_A["Private<br/>10.0.11.0/24"]
            DATA_A["Data<br/>10.0.21.0/24"]
        end

        subgraph AZ_B["AZ-b"]
            PUB_B["Public<br/>10.0.2.0/24"]
            PRIV_B["Private<br/>10.0.12.0/24"]
            DATA_B["Data<br/>10.0.22.0/24"]
        end

        subgraph AZ_C["AZ-c"]
            PUB_C["Public<br/>10.0.3.0/24"]
            PRIV_C["Private<br/>10.0.13.0/24"]
            DATA_C["Data<br/>10.0.23.0/24"]
        end

    end

    IGW --> PUB_A & PUB_B & PUB_C
    PUB_A -->|NAT| PRIV_A
    PUB_B -->|NAT HA| PRIV_B
    PUB_C -->|NAT HA| PRIV_C
    PRIV_A --> DATA_A
    PRIV_B --> DATA_B
    PRIV_C --> DATA_C

    style PUB_A fill:#1a472a,stroke:#2d6a4f,color:#fff
    style PUB_B fill:#1a472a,stroke:#2d6a4f,color:#fff
    style PUB_C fill:#1a472a,stroke:#2d6a4f,color:#fff
    style PRIV_A fill:#1b3a4b,stroke:#2a6f97,color:#fff
    style PRIV_B fill:#1b3a4b,stroke:#2a6f97,color:#fff
    style PRIV_C fill:#1b3a4b,stroke:#2a6f97,color:#fff
    style DATA_A fill:#4a1942,stroke:#7b2d8e,color:#fff
    style DATA_B fill:#4a1942,stroke:#7b2d8e,color:#fff
    style DATA_C fill:#4a1942,stroke:#7b2d8e,color:#fff
```

---

## 4. Application Data Flow

```mermaid
graph LR
    USER["👤 User"] -->|HTTPS| WAF["WAF"] --> ALB["ALB"]

    subgraph COMPUTE["Compute Layer (any phase)"]
        UI["Web UI<br/>nginx"]
        GW["API Gateway<br/>Flask"]
        OS["Order Service"]
        PS["Payment Service"]
        NW["Notification Worker"]
        IW["Inventory Worker"]
    end

    subgraph DATA["Data Layer (shared, Multi-AZ)"]
        PG["RDS PostgreSQL<br/>Multi-AZ"]
        RD["ElastiCache Redis<br/>Replication Group"]
        KF["MSK Kafka<br/>TLS encrypted"]
    end

    ALB --> UI & GW & GRAF

    UI -->|"reverse proxy"| GW
    GW -->|HTTP| OS
    OS -->|HTTP| PS
    OS -->|SQL| PG
    OS -->|cache| RD
    OS -->|produce| KF
    KF -->|consume| NW
    KF -->|consume| IW
    NW -->|SQL| PG
    IW -->|SQL| PG

    subgraph OBS["Observability (dual-stack)"]
        OTEL["OTel Collector"]
        PROM["Prometheus"]
        LOKI["Loki"]
        TEMPO["Tempo"]
        GRAF["Grafana"]
        AM["Alertmanager"]
        CW2["CloudWatch<br/>Container Insights"]
    end

    GW & OS & PS & NW & IW -->|"OTLP"| OTEL
    OTEL --> PROM & LOKI & TEMPO
    PROM & LOKI & TEMPO --> GRAF
    PROM --> AM
    GW & OS & PS & NW & IW -.->|"awslogs"| CW2
```

---

## 5. Security & Access Flow

```mermaid
graph TB
    DEV["👨‍💻 Developer"]
    GHA["GitHub Actions"]

    subgraph AUTH["CI/CD Authentication"]
        OIDC["OIDC Provider"]
        STS["AWS STS"]
        IAM_ECR["IAM Role: ecr-push"]
        IAM_DEP["IAM Role: deploy"]
    end

    subgraph EDGE_SEC["Edge Security"]
        WAF2["WAF v2"]
        RATE["Rate Limiting"]
        MANAGED["Managed Rules:<br/>CommonRuleSet<br/>SQLiRuleSet<br/>XSSRuleSet"]
    end

    subgraph ACCESS["Infrastructure Access"]
        SSM_SM["SSM Session Manager"]
        BAST["Bastion Host"]
    end

    subgraph SECRETS["Secrets Management"]
        SM["Secrets Manager<br/>Auto Rotation"]
        KMS2["KMS CMK"]
    end

    subgraph ROLES["Workload Roles"]
        ECS_EXEC["ECS Execution Role"]
        ECS_TASK["ECS Task Role"]
        EKS_NODE["EKS Node Role"]
        EKS_IRSA["EKS Pod Role IRSA"]
    end

    GHA -->|"JWT"| OIDC --> STS --> IAM_ECR & IAM_DEP
    DEV -->|"SSM"| SSM_SM --> BAST
    WAF2 --- RATE & MANAGED
    SM -.->|"encrypted by"| KMS2
    ECS_EXEC & ECS_TASK -.-> SM

    style AUTH fill:#1b3a4b,stroke:#2a6f97,color:#fff
    style EDGE_SEC fill:#3d1c02,stroke:#b85c1e,color:#fff
    style SECRETS fill:#4a1942,stroke:#7b2d8e,color:#fff
```

---

## 6. CI/CD Pipeline

```mermaid
graph LR
    DEV["Developer"] -->|push| GH["GitHub<br/>main branch"]
    GH -->|trigger| WF["GitHub Actions"]

    WF -->|"1. OIDC"| STS["AWS STS"] -->|"temp creds"| WF
    WF -->|"2. Build"| IMG["Docker Build"]
    IMG -->|"3a."| ECR["AWS ECR"]
    IMG -->|"3b."| GHCR["GitHub GHCR"]

    WF -->|"4. Deploy"| DEPLOY{"Phase?"}
    DEPLOY -->|8A/8B| ECS["ECS Update"]
    DEPLOY -->|8C/8D| EKS["kubectl apply"]

    style WF fill:#1b3a4b,stroke:#2a6f97,color:#fff
    style DEPLOY fill:#5c2a0a,stroke:#b85c1e,color:#fff
```

---

## Quick Reference

| Layer | Components | Subnet | Production Additions |
|-------|-----------|--------|---------------------|
| **Edge** | Route53, ACM, ALB | Public | + WAF v2, Rate Limiting |
| **Compute** | ECS/EKS (4 phases) | Private | (unchanged) |
| **Data** | RDS, Redis, MSK, EFS | Data | + Multi-AZ, Backup, KMS, TLS |
| **Observability** | Prometheus, Grafana, Loki, Tempo | Private | (unchanged) |
| **Management** | Bastion, SSM | Public | (unchanged) |
| **CI/CD** | OIDC, GitHub Actions | External | (already production-grade) |
| **State** | Terraform state | — | + S3 Backend, DynamoDB Lock |
| **Secrets** | SSM, Secrets Manager | — | + Auto Rotation, KMS |
