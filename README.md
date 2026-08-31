# DevOps Project — Infrastructure, CI/CD, Monitoring & Logging

An end-to-end reference implementation of a production-style DevOps stack on
AWS: Terraform-provisioned infrastructure, GitHub Actions CI/CD with a
manual production approval gate, and monitoring/centralized logging with
ready-made dashboards.

```
.
├── terraform/            # Part 1 — infrastructure as code
├── app/                  # Sample Node.js/Express service used by the pipelines
├── .github/workflows/    # Part 2 — CI/CD pipelines
├── monitoring/           # Part 3 — Prometheus/Grafana + Fluent Bit reference stack
├── docs/architecture.md  # Architecture diagram & decisions
└── SECURITY.md           # Security considerations
```

## Part 1: Infrastructure (Terraform)

Provisions, in `terraform/`:

| Resource | File | Notes |
|---|---|---|
| VPC, public + private (app & db) subnets, IGW, NAT | `vpc.tf` | 2 AZs by default; VPC Flow Logs to CloudWatch |
| Security groups | `security_groups.tf` | Chained ALB -> app -> db trust, no open SSH |
| ECS Fargate cluster, service, task definition, autoscaling | `ecs.tf` | See "Why Fargate" in `docs/architecture.md` |
| ECR repository | `ecs.tf` | Immutable tags, scan-on-push |
| RDS PostgreSQL | `rds.tf` | Encrypted, private, automated backups, AWS Backup plan |
| Secrets Manager | `rds.tf` | Auto-generated DB password, never in state as a variable |
| Application Load Balancer | `alb.tf` | Public frontend, access logs to S3 |
| CloudWatch alarms & dashboards | `monitoring.tf` | Infra + app + DB metrics, SNS notifications |
| Outputs | `outputs.tf` | ALB DNS, ECR URL, RDS endpoint, dashboard URLs, etc. |
| Variables | `variables.tf` | All configurable — region, sizing, environment, retention, etc. |

### Setup & usage

**Prerequisites:** Terraform >= 1.5, an AWS account, AWS CLI configured with
credentials that can create the resources above.

1. **Bootstrap the remote state backend** (one-time, per AWS account — see
   the comment block in `terraform/versions.tf` for the exact commands):
   ```bash
   aws s3api create-bucket --bucket <your-tfstate-bucket> --region us-east-1
   aws s3api put-bucket-versioning --bucket <your-tfstate-bucket> \
     --versioning-configuration Status=Enabled
   aws dynamodb create-table --table-name terraform-locks \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST
   ```
2. **Configure variables:**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars   # edit values as needed (git-ignored)
   cp backend-staging.hcl.example backend-staging.hcl  # fill in your bucket/table names
   ```
3. **Initialize, plan, apply:**
   ```bash
   terraform init -backend-config=backend-staging.hcl
   terraform plan -var-file=terraform.tfvars
   terraform apply -var-file=terraform.tfvars
   ```
4. **Retrieve outputs** (ALB URL, ECR repo, RDS endpoint, dashboard links):
   ```bash
   terraform output
   ```
5. For production, repeat with `backend-production.hcl.example` and
   `-var="environment=production"`, and review the production-specific
   variable overrides called out in `terraform.tfvars.example` (Multi-AZ,
   deletion protection, final snapshot).

To tear down: `terraform destroy -var-file=terraform.tfvars` (production has
`deletion_protection`/`skip_final_snapshot` guards on by default — see
`variables.tf`).

## Part 2: CI/CD (GitHub Actions)

Three workflows in `.github/workflows/`:

- **`ci.yml`** — runs on every PR: lint, unit tests, integration tests
  against a real Postgres service container, `npm audit` + Trivy dependency
  scan, a Docker build + Trivy image scan, and `terraform fmt/validate` +
  `tfsec`. Notifies Slack/email on failure.
- **`cd.yml`** — runs on merge to `main`: builds the image, scans it
  (blocking on CRITICAL CVEs), pushes to ECR, deploys to **staging**
  automatically (new task-definition revision, rolling `ecs update-service`,
  waits for stability, smoke-tests `/health`), then deploys to
  **production** — gated behind the `production` GitHub Environment's
  required-reviewer approval.
- **`terraform.yml`** — plans infra changes on PRs touching `terraform/`,
  applies to staging automatically on merge, and applies to production only
  after the same manual-approval gate.

### Setup

1. In **Settings -> Environments**, create `staging` and `production`
   environments; add one or more required reviewers to `production`.
2. Add these repository secrets:
   - `AWS_DEPLOY_ROLE_ARN`, `AWS_DEPLOY_ROLE_ARN_PROD` — IAM roles CI assumes
     via OIDC to deploy to ECS (scope to `ecs:*` on the relevant
     cluster/service + `ecr:*` on the repo, nothing broader).
   - `AWS_TERRAFORM_ROLE_ARN`, `AWS_TERRAFORM_ROLE_ARN_PROD` — broader IAM
     role for `terraform apply` (create/modify the resources in `terraform/`).
   - `SLACK_WEBHOOK_URL` — for pipeline failure/success notifications.
   - `NOTIFY_EMAIL`, `SMTP_USERNAME`, `SMTP_PASSWORD` — optional email
     notification path.
3. Push to `main` (or merge a PR) to trigger the pipeline.

## Part 3: Monitoring & Logging

**In AWS** (always-on, provisioned by Terraform):
- **Infrastructure metrics** — ECS CPU/memory/running-task-count via
  Container Insights (`monitoring.tf`).
- **Application metrics** — ALB request count, 4xx/5xx error counts, target
  response time (p50/p99), healthy/unhealthy host count.
- **Database metrics** — RDS CPU, freeable memory, free storage, connection
  count, via Enhanced Monitoring + Performance Insights.
- **Two CloudWatch dashboards**: `<project>-<env>-infrastructure` and
  `<project>-<env>-application` (URLs in `terraform output`).
- **Alarms** for all of the above, fanning into an SNS topic (email and/or
  Slack via AWS Chatbot).
- **Centralized logging**: application logs via the `awslogs` driver to
  CloudWatch Logs (`/ecs/<project>-<env>`), system/network logs via VPC Flow
  Logs, access logs via ALB access logging to S3, and RDS logs
  (`postgresql`, `upgrade`) exported to CloudWatch Logs.

**Local / reference stack** (`monitoring/`, optional — for local dev or a
non-AWS deployment):
```bash
cd monitoring
docker compose -f docker-compose.monitoring.yml up
```
- Prometheus (`:9090`) scrapes the app's `/metrics` endpoint, node-exporter
  (host metrics), cAdvisor (container metrics), and postgres-exporter (DB
  metrics), evaluating the alert rules in `prometheus/alert-rules.yml`.
- Grafana (`:3001`, default password `changeme` via `GRAFANA_ADMIN_PASSWORD`)
  auto-provisions the **Infrastructure Overview** and **Application
  Overview** dashboards from `monitoring/grafana/dashboards/`.
- Fluent Bit tails container/system logs and ships them (stdout sink by
  default; swap in the commented-out `cloudwatch_logs` output block to point
  at real CloudWatch Logs, or reuse the same config as an ECS FireLens
  sidecar).

## Part 4: Documentation & Best Practices

- **Architecture decisions**: `docs/architecture.md` (diagram, why Fargate,
  subnet design, state management, secrets, deployment strategy).
- **Security considerations**: `SECURITY.md` (network, IAM, secrets, data
  protection, vulnerability scanning).
- **Secret management**: AWS Secrets Manager for the RDS password (see
  `terraform/rds.tf`), OIDC-based short-lived credentials for CI/CD (no
  static AWS keys in GitHub secrets).
- **Backup strategy**: RDS automated backups (7-day retention, defined
  backup window) plus an independent AWS Backup plan (daily, 35-day
  retention) covering the RDS instance — see `terraform/rds.tf`.

### Cost optimization measures

- Fargate (pay-per-task) instead of always-on EC2 instances; autoscaling
  bounded at 2–6 tasks by default.
- `db.t4g.micro` (Graviton, burstable) as the default RDS instance class;
  Multi-AZ is opt-in (`db_multi_az`), not default, for non-production.
- A single shared NAT gateway by default (`single_nat_gateway = true`) —
  switch to one-per-AZ only where the extra resilience is worth the cost
  (recommended for production).
- ECR lifecycle policy expires untagged images after 14 days; ALB access
  logs expire after 90 days via S3 lifecycle rules.
- RDS storage autoscaling (`max_allocated_storage`) avoids over-provisioning
  disk up front.
- FARGATE_SPOT is registered as an available capacity provider for
  non-critical/staging workloads that can tolerate interruption.

### Assumptions & scope notes

- The sample application in `app/` is intentionally minimal (Express +
  `/health` + `/metrics` + a couple of demo routes) — it exists to give the
  pipelines something real to build, test, scan, and deploy, not as the
  focus of the exercise.
- `container_image` defaults to a public placeholder image so
  `terraform apply` succeeds standalone before the CD pipeline has pushed a
  real image; the CD pipeline updates the running task definition's image
  directly via `aws ecs register-task-definition`, independent of the
  Terraform-managed default.
- ACM/HTTPS listener, Route 53 records, and a WAF are stubbed/commented
  where relevant rather than fully wired up, since they require a domain
  name and certificate the reader supplies.
