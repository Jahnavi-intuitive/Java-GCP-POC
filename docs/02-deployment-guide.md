# Deployment Guide

All commands are for Windows PowerShell. If scripts are blocked, run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` in that window, or call `gcloud.cmd` instead of `gcloud`.

## 1. Prerequisites

| Tool | Used for |
|---|---|
| Google Cloud CLI (`gcloud`), logged in with access to project `itp-agentspace` | Cloud operations and identity tokens |
| Terraform 1.6 or newer | Infrastructure |
| Docker Desktop | Local `docker compose` and the k6 image |
| Git and a GitHub account with the repository | Source and CI/CD |

## 2. One-time bootstrap

1. Create a Cloud Storage bucket for the Terraform state (`trebol-poc-tfstate-itp-agentspace`) with versioning enabled. Terraform stores its state here (`prefix trebol/prod`).
2. Create `infra/terraform/terraform.tfvars` (git-ignored) with `project_id` and `image` (the image tag to deploy first). Never commit this file.
3. From `infra/terraform`: `terraform init`, then `terraform plan`, then `terraform apply`.

Terraform creates: the required APIs, the VPC and subnet, private services access, Artifact Registry (with cleanup policies), Cloud SQL (private IP only, SSL required, backups, deletion protection), Secret Manager secrets, three service accounts and their roles, the Cloud Run service, Workload Identity Federation for GitHub, and the monitoring stack.

4. **Admin password hash (manual, by design).** The secret `trebol-poc-admin-password-hash` is created empty by Terraform and the value is added by hand, so the hash never passes through Terraform state or the repository. Generate a bcrypt hash and add it as a new secret version.

## 3. GitHub configuration

Add these as **repository variables** (Settings, Secrets and variables, Actions, Variables). They are identifiers, not secrets. No secret is stored in GitHub.

`GCP_PROJECT_ID`, `GCP_REGION`, `GCP_WIF_PROVIDER`, `GCP_PUSH_SA`, `GCP_DEPLOY_SA`, `GCP_SERVICE_URL`. Optional: `TRIVY_BLOCK=true` makes the vulnerability scan fail the build.

Values come from `terraform output`.

## 4. Pipeline behaviour

**On every pull request** (`.github/workflows/pr.yml`):
1. Build and run unit tests with Maven; coverage by JaCoCo is written to the run summary.
2. Lint the Dockerfile with hadolint.
3. For pull requests from this repository: build the image (linux/amd64), scan it with Trivy (HIGH and CRITICAL, reported in the run summary), and push it to Artifact Registry tagged with the commit SHA and `pr-<number>`.

**On every push to `main` that touches application code** (`.github/workflows/deploy.yml`):
1. Build and push the image tagged with the commit SHA.
2. Deploy a new Cloud Run revision with 0% traffic and a `canary` tag.
3. Smoke-test the canary URL (liveness and readiness).
4. Send 10% of traffic to the canary and run a bake check (60 requests; fail if more than 1 fails).
5. Promote to 100% on success; on any failure, restore 100% to the previous revision (automatic rollback).
6. Publish the result (revision, previous revision, bake failures, commit) to the run summary.

Changes that touch only `docs/`, `infra/`, `loadtest/`, `scripts/`, `.github/` or Markdown files do not trigger a deploy. The deploy identity can only be used from the `main` branch.

**The stack must be up** (database running) when a deploy runs, otherwise the new revision cannot pass its probes.

## 5. Day-to-day operation (cost control)

```powershell
.\scripts\poc.ps1 up       # database ALWAYS, Cloud Run min instances 2, health check
.\scripts\poc.ps1 status   # shows current state
.\scripts\poc.ps1 down     # Cloud Run min 0, database stopped
```

The script refuses to run against any project other than `itp-agentspace`.

## 6. Calling the private service

The service requires a Google identity token. The application's own JWT filter reads `Authorization`, so send the Google token in `X-Serverless-Authorization`:

```powershell
$TOKEN = gcloud.cmd auth print-identity-token
curl.exe -H "X-Serverless-Authorization: Bearer $TOKEN" "<service url>/actuator/health/readiness"
```

Expected: HTTP 200 with `{"status":"UP"}`.

## 7. Public access (open item)

The organisation's domain-restricted-sharing policy rejects granting `allUsers` the invoker role, so the service URL is HTTPS but not open to the internet. Terraform contains a switch (`allow_public_access`, default `false`). Options: an organisation-policy exception for this project, or invoker rights granted to named evaluators or a company group.

## 8. Rollback and recovery

- **Automatic:** the deploy workflow restores the previous revision if the smoke test or bake check fails.
- **Manual:** `gcloud run services update-traffic trebol-poc-app --region us-central1 --to-revisions <previous-revision>=100`.
- After a rollback, traffic stays pinned to the old revision until the next successful deploy.

## 9. Teardown

Cloud SQL has deletion protection enabled on purpose, so `terraform destroy` will refuse until it is lifted deliberately. Do not run destroy in this shared project without an explicit decision.

## 10. Image build details

`trebol-backend-monolith/Dockerfile` (multi-stage, non-root).

**Build stage**

| Change | Effect |
|---|---|
| Maven dependency download in its own cached layer, plus a BuildKit cache mount for `~/.m2` | Dependencies are not re-downloaded between builds |
| The error-ignoring fallback (`true` after the download command) removed | Download failures now fail the build |
| WAR unpacked into Spring Boot layers | Dependency layer separate from application code |
| Application classes packaged as a jar | Class data sharing (CDS) can only archive classes from jars |
| `lombok` (compile-time only) and `swagger-ui` (disabled in prod) deleted from the image | Smaller image, less attack surface |

**Runtime stage**

| Change | Effect |
|---|---|
| Only the classpath layers are copied: dependencies, then the app-classes jar | Unused Spring loader and snapshot layers removed |
| `COPY --link` with numeric ownership 65532 (`--link` cannot resolve the name `nonroot`) | A small app change does not invalidate the large dependency layer |
| One `CLASSPATH` definition used by both the training run and the entrypoint | CDS needs them identical |
| AppCDS: a training run builds `/app/app-cds.jsa`, an archive of loaded classes the JVM maps at startup, run with the same JVM as the app | Faster startup |
| JVM flags: SerialGC, C1-only JIT (`TieredStopAtLevel=1`), `-Xss512k`, the CDS archive file, plus the original two flags | Lower start-up cost and memory |
| Entrypoint `java org.trebol.BackendApp` | Direct start from the classpath |

**Measured effect:** startup about 21 s before, about 6 s after (1 CPU, idle laptop); image size 463 MB before, about 583 MB after (mostly the CDS archive).

## 11. Current runtime configuration

| Component | Setting |
|---|---|
| Cloud Run | min 2, max 30, concurrency 10, 2 vCPU / 2 GiB, request-based CPU (idle throttling), startup CPU boost |
| Cloud SQL | MySQL 8.0, `db-custom-2-7680` (2 vCPU, 7.5 GB), running, 10 GB SSD (auto-resize limit 20 GB), private IP, SSL required |

The Terraform files in the repository still hold the earlier defaults (1 vCPU / 1 GiB, concurrency 80, max 10, `db-f1-micro`).
