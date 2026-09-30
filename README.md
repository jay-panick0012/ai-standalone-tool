# AI Pipeline & Environment Generator — standalone

A small, self-hosted version of the generator tool. It runs as one Docker
container: a static frontend plus a lightweight Node/Express backend that
calls the Anthropic API directly. No claude.ai dependency, no repo access
to the target project needed — everything comes in through paste-in fields.

Three modes:
- **Generate from scratch** — describe an environment/pipeline in plain English,
  get back one IaC snippet and one pipeline snippet.
- **Review & improve existing code** — paste an existing (redacted) pipeline
  or IaC snippet, or upload it: a `.zip` of the repo/folder, or individual
  IaC/pipeline files (Terraform, Bicep, CloudFormation, ARM, Dockerfile,
  Azure Pipelines, GitHub Actions, Jenkinsfile, GitLab CI, etc.), and get
  back the issues found plus an improved version. A zip is unzipped entirely
  in the browser (JSZip) and each file is auto-sorted into the IaC field or
  the pipeline field by filename/content; `.tfstate`, `.pem`/`.key`, `.env`,
  and similar secret/state files are filtered out automatically, and
  build/vendor directories (`node_modules`, `.git`, `dist`, etc.) are
  skipped. Review the populated fields before generating — nothing is sent
  to the backend until you click Generate. Use this when testing against a
  real project's files.
- **Full solution bundle** — describe an end-to-end need (e.g. "onboard a new
  client across dev/qa/staging/prod") and get back a *complete* file set:
  environment-separated IaC, a full multi-stage pipeline with security gates,
  and a README explaining how to adopt it — downloadable as a single .zip.
  This is the "end-to-end" mode: it hands back a full solution to review and
  drop into a repo, not a fragment to build the rest around.

  There's also a disabled "Push to Git" button next to the download button.
  It's intentionally not wired up yet — it needs real repo credentials
  (a PAT or GitHub App / Azure DevOps service connection) per project, which
  don't exist under the current access model. `/api/push-to-git` on the
  backend returns a clear 501 explaining why, and is where that integration
  plugs in later without touching the generation logic — it would reuse the
  same `files` array `/api/generate-solution` already produces, just commit
  it to a new branch and open a PR instead of zipping it.

## Before you paste anything in

Redact account IDs, subscription IDs, hostnames, internal IPs, and —
critically — never paste real secret values or credentials, even for a
project whose pain point *is* secrets in the repo. Use obvious placeholders
(`ACCOUNT_ID`, `<SUBSCRIPTION_ID>`, `REDACTED`) instead.

## 1. Get an Anthropic API key

Create one at https://console.anthropic.com (Settings → API Keys). This is
separate from any claude.ai seat — it's billed per API call. Costs for this
tool are small (a few cents per generation) but are real once deployed.

## 2. Run it locally first

```bash
cp .env.example .env
# edit .env and paste in your ANTHROPIC_API_KEY
docker compose up --build
```

Open http://localhost:8080 and confirm both modes work before deploying
anywhere. `GET /api/health` should return `{"status":"ok","configured":true}`.

## 3. Deploy — same image, either cloud

Build once, push to whichever registry the target cloud uses:

```bash
docker build -t ai-pipeline-generator:latest .
```

### Option A — AWS (ECS Fargate, or App Runner for less setup)

1. Push the image to Amazon ECR:
   ```bash
   aws ecr create-repository --repository-name ai-pipeline-generator
   aws ecr get-login-password | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com
   docker tag ai-pipeline-generator:latest <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/ai-pipeline-generator:latest
   docker push <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/ai-pipeline-generator:latest
   ```
2. Store `ANTHROPIC_API_KEY` in AWS Secrets Manager, not as a plain environment
   variable, and reference the secret from the task definition.
3. Simplest path: **App Runner** — point it at the ECR image, map the secret,
   expose port 8080. No VPC/ALB setup needed for a quick internal pilot.
   More control: **ECS Fargate** behind an internal ALB if it needs to sit
   inside a private VPC the project team already trusts.

### Option B — Azure (Container Apps, or App Service for Containers)

1. Push the image to Azure Container Registry:
   ```bash
   az acr create --name <REGISTRY_NAME> --resource-group <RG> --sku Basic
   az acr login --name <REGISTRY_NAME>
   docker tag ai-pipeline-generator:latest <REGISTRY_NAME>.azurecr.io/ai-pipeline-generator:latest
   docker push <REGISTRY_NAME>.azurecr.io/ai-pipeline-generator:latest
   ```
2. Store `ANTHROPIC_API_KEY` in Azure Key Vault and reference it as a secret
   in the container app / app service configuration — not a plain app setting.
3. Simplest path: **Azure Container Apps** — `az containerapp create` pointing
   at the ACR image, with the Key Vault secret mounted as an env var, port 8080.

Either way, the only cloud-specific work is the secret store and the
container host — the image itself is identical, which is the point: it can
run in Experion's own cloud ops account for internal testing, or be hosted
inside the client's subscription/account if they'd rather it stay on their
side, without any code changes.

## 4. What it needs from each project team

Nothing ongoing. One-time ask per project:
- One existing pipeline file (YAML), redacted
- One existing IaC file if any exists (Terraform/Bicep/CloudFormation), redacted
- A sentence or two on what's slow or painful about it today

That's enough to run the "review & improve" mode and show a credible
before/after without needing repo access, CI integration, or their time
beyond sending two files.

## Notes on cost and safety

- The API key lives only in the backend's environment/secret store — the
  browser never sees it.
- Every request is logged server-side only for error diagnostics (see
  `console.error` calls in `server/index.js`); nothing is persisted to disk
  or a database in this minimal version.
- If you want to keep a history of generations, add a small database (or
  even a JSON file for a pilot) — not included here to keep the first
  deployment as simple as possible.
