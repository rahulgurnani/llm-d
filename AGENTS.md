# AGENTS.md

Guide for AI coding agents working in this repository.

## What This Repo Is

**llm-d** is a Kubernetes-native distributed LLM inference serving stack. It is a documentation and configuration repo — it contains Helm values, Kustomize manifests, shell scripts, Dockerfiles, and deployment guides. There is no application source code to compile or unit-test here.

The primary outputs are:
- **Well-lit path guides** (`guides/`) — tested, benchmarked recipes for deploying vLLM + the llm-d router on Kubernetes.
- **Container image build infrastructure** (`docker/`) — Dockerfiles for CUDA, ROCm, HPU, and RDMA-tools images.
- **Helper scripts** (`scripts/`, `helpers/`) — linting, benchmarking, and environment setup utilities.

## Repository Layout

```
guides/                  # Deployment guides, one directory per pattern
  optimized-baseline/    # Prefix-cache + load-aware routing (recommended starting point)
  pd-disaggregation/     # Prefill/decode disaggregation
  wide-ep-lws/           # Wide expert-parallelism (MoE)
  predicted-latency-routing/
  precise-prefix-cache-routing/
  tiered-prefix-cache/
  flow-control/
  workload-autoscaling/
  rollouts/
  asynchronous-processing/   # Experimental
  batch-gateway/             # Experimental
  prereq/                    # Shared prerequisites (gateways, model servers, etc.)
  recipes/                   # Reusable Helm values snippets
docs/                    # Architecture docs, proposals, accelerator notes
docker/                  # Dockerfiles and build scripts per accelerator
scripts/                 # Linting and CI utilities
helpers/                 # Benchmark tooling, HF token setup
hooks/                   # Git pre-commit hooks
.github/workflows/       # CI: PR checks, nightly e2e, image builds, releases
```

## Conventions to Follow

### Guides Structure

Each guide directory follows the same pattern:
- `README.md` — the user-facing deployment guide
- `router/` — Helm values for the llm-d router
- `modelserver/` — Kustomize overlays for vLLM pods
- `benchmark-templates/` — load test configurations (where applicable)

When editing a guide, keep all code blocks copy-paste ready — users run them verbatim. Environment variables must be set via `export` before use and must be consistent across all code blocks in the guide.

### Environment Variables in Shell Scripts

All scripts under `docker/scripts/` must declare required env vars in a standardized header block. The linter (`scripts/lint-envvars.py`) enforces this. Format:

```bash
# Required environment variables:
# - VAR_NAME: description
```

Run the linter before committing changes to any script:
```bash
./scripts/lint-envvars.py docker/scripts/path/to/script.sh
```

### Commit Requirements

Every commit **must** include a DCO sign-off line:
```
Signed-off-by: Your Name <you@example.com>
```
Add it automatically with `git commit -s`. PRs without DCO sign-off will be blocked by CI.

### Proposals for New Features

Changes that introduce new public APIs, new components, or cross-cutting behavior require a project proposal markdown file at `docs/proposals/<descriptive-name>.md` using the template at `docs/proposals/PROPOSAL_TEMPLATE.md`. Do not open implementation PRs for such changes without an approved proposal.

Bug fixes and small targeted changes do not require a proposal.

### Experimental vs. Core

- Experimental features must be **off by default** and clearly labeled as experimental in docs and any flag names (e.g., `--experimental-*`).
- Experimental guides live in a clearly marked section of `guides/README.md`.
- Do not graduate an experimental feature to stable without maintainer sign-off.

## CI / Testing

There is no local unit test suite to run. Verification is done via:

1. **Kustomize dry-run** (`ci-kustomize-dry-run.yaml`) — validates all kustomize overlays render without error.
2. **Pre-commit linting** — env var linting, typo checking, Dockerfile linting. Run hooks manually via `pre-commit run --all-files` if the hook tooling is installed.
3. **Nightly e2e** — runs full deployment tests on real clusters (GKE, OpenShift, CoreWeave). These are not runnable locally.

For any PR, CI checks that matter are `ci-pr-checks.yaml` and `ci-kustomize-dry-run.yaml`. Make sure these pass.

## What Agents Should and Should Not Do

**Do:**
- Edit `README.md` files in guides to fix accuracy, improve clarity, or update version numbers.
- Update Helm values files (`values.yaml`, `values-*.yaml`) in `guides/*/router/` and `guides/*/modelserver/`.
- Update Kustomize overlays (`kustomization.yaml`, patch files) in guide directories.
- Fix env var declarations in `docker/scripts/` shell scripts to satisfy the linter.
- Keep code blocks in guides consistent when environment variables or version pins change.

**Do not:**
- Commit without a DCO sign-off (`git commit -s`).
- Remove or rename environment variables exported in guide `README.md` files without updating every downstream reference in the same guide.
- Introduce new Docker base images or add external dependencies without maintainer discussion.
- Mark experimental guides as stable without approval.
- Break the kustomize dry-run — always check that `kubectl kustomize` succeeds on any overlay you touch.
- Add speculative error handling or defensive abstractions not required by the immediate task.

## Writing Nightly E2E Tests

Nightly tests live in `.github/workflows/nightly-e2e-<guide-name>-<platform>.yaml`. Each file is a thin wrapper that calls a reusable workflow from `llm-d/llm-d-infra` — no test logic lives in this repo.

### File Naming

```
nightly-e2e-<guide-name>-<platform>.yaml
```

Platforms in use: `gke`, `ocp` (OpenShift), `cks` (CoreWeave), `gke-tpu`, `xpu`, `hpu`.

Examples: `nightly-e2e-optimized-baseline-gke.yaml`, `nightly-e2e-wide-ep-lws-ocp.yaml`.

### Minimal Workflow Template

```yaml
name: Nightly - <Human Readable Guide Name> E2E (<PLATFORM>)

# One-line description of what this test covers.

on:
  schedule:
    - cron: '0 10 * * *'  # HH:MM UTC daily (staggered from <other nightly> at HH:MM)
  workflow_dispatch:
    inputs:
      skip_cleanup:
        description: 'Skip cleanup after tests (for debugging)'
        required: false
        default: 'false'
      pr_number:
        description: 'PR number for comment-back (set by /test-nightly)'
        required: false
        default: ''
      pr_repo:
        description: 'Repo for PR comment-back'
        required: false
        default: 'llm-d/llm-d'

permissions:
  contents: read

concurrency:
  group: nightly-e2e-<guide-name>-<platform>
  cancel-in-progress: true

jobs:
  nightly:
    if: github.repository == 'llm-d/llm-d'
    uses: llm-d/llm-d-infra/.github/workflows/reusable-nightly-e2e-<platform>.yaml@main
    with:
      guide_name: <guide-name>
      namespace: llm-d-nightly-<short-guide>-<platform>
      gateway_host: '<guide-name>-epp'
      custom_deploy_script: |
        export GAIE_VERSION=v1.5.0
        export ROUTER_CHART_VERSION=v0
        export GUIDE_NAME="<guide-name>"
        export INFRA_PROVIDER="<platform>"
        kubectl apply -n ${NAMESPACE} -k guides/${GUIDE_NAME}/modelserver/gpu/vllm/${INFRA_PROVIDER}
        helm install ${GUIDE_NAME} \
          oci://ghcr.io/llm-d/charts/llm-d-router-standalone-dev \
          -f guides/recipes/router/base.values.yaml \
          -f guides/${GUIDE_NAME}/router/${GUIDE_NAME}.values.yaml \
          -n ${NAMESPACE} --version ${ROUTER_CHART_VERSION}
      required_gpus: 2
      recommended_gpus: 4
      accelerator_type: H100
      pod_wait_timeout: '30m'
      pod_readiness_delay: 0
      image_override: 'ghcr.io/llm-d/llm-d-cuda-dev:latest'
      allow_gpu_preemption: true
      skip_cleanup: ${{ github.event.inputs.skip_cleanup == 'true' }}
      pr_number: ${{ github.event.inputs.pr_number }}
      pr_repo: ${{ github.event.inputs.pr_repo }}
    secrets: inherit
```

### Required Fields and Rules

| Field | Rule |
|---|---|
| `permissions` | Always `contents: read` — never elevate. |
| `concurrency.group` | `nightly-e2e-<guide-name>-<platform>` — must be unique per file. |
| `if: github.repository == 'llm-d/llm-d'` | Always present — prevents forks from running against shared clusters. |
| `namespace` | Pattern: `llm-d-nightly-<short-guide>-<platform>`. Use consistent short names (e.g., `pd` for pd-disaggregation, `wide-ep` for wide-ep-lws). |
| `image_override` | Always use the `-dev` floating tag (`ghcr.io/llm-d/llm-d-cuda-dev:latest`). Never pin to a specific digest in a nightly. |
| `custom_deploy_script` | Must mirror the guide's README install steps exactly — same `kubectl apply -k` and `helm install` commands, same flags. Drift here causes false passes. |
| `skip_cleanup` / `pr_number` / `pr_repo` | All three must be present as `workflow_dispatch` inputs — required by the `/test-nightly` slash command. |

### Cron Scheduling

Nightlies are staggered to avoid saturating shared GPU clusters. Current schedule boundaries:

- `23:00 UTC` — nightly image build (must complete before any e2e)
- `00:00–06:00 UTC` — OpenShift (OCP) nightlies
- `06:00–08:00 UTC` — CKS (CoreWeave) nightlies
- `10:00–13:00 UTC` — GKE nightlies

When adding a new nightly, pick a slot in the appropriate platform window with at least 30 minutes of gap from adjacent jobs on the same platform. Add a comment on the cron line explaining the offset:

```yaml
- cron: '30 10 * * *'  # 10:30 UTC daily (staggered from optimized-baseline-gke at 10:00)
```

### Pre-deploy Dependencies

If the guide requires extra cluster prerequisites (e.g., LeaderWorkerSet CRDs for `wide-ep-lws`), use a `pre_deploy_script` block. Always guard installs with an existence check to make idempotent:

```yaml
pre_deploy_script: |
  if ! kubectl get crd <crd-name> &>/dev/null; then
    helm install ...
  fi
```

### Slim Transforms for Resource-Constrained Platforms

Some platforms (OpenShift nightly clusters) have fewer GPUs than the production guide requires. For these, create a `nightly` kustomize overlay under `guides/<guide-name>/modelserver/gpu/vllm/nightly/` that swaps in a smaller model (e.g., `Qwen/Qwen3-0.6B` instead of DeepSeek-R1) and reduces GPU counts. Document the swap clearly in the workflow comment header.

### Registering with `/test-nightly`

After adding a new workflow file, register its name in `.github/workflows/slash-test-nightly.yaml` in two places:

1. The `E2E_NIGHTLIES` array in the `Parse command` step (the part after `nightly-e2e-` in the filename).
2. The comment block at the top of the file listing available nightlies.

Failing to do this means `/test-nightly <your-guide>` will return "Unknown nightly" for all PR contributors.

### GKE-Specific Fields

GKE workflows require two extra fields not present in OCP/CKS:

```yaml
gke_cluster_name: llm-d-e2e-us-east5   # or llm-d-e2e-us-south1-2 for H200
gke_cluster_zone: us-east5
llm_d_ref: ${{ github.ref }}
```

Use `us-east5` (H100) for standard guides and `us-south1` (H200) for guides requiring higher memory (pd-disaggregation, wide-ep-lws).

## Key Version Variables

Guides pin component versions via exported shell variables. Common ones:
- `GAIE_VERSION` — Gateway API Inference Extension CRD version
- `ROUTER_CHART_VERSION` — llm-d router Helm chart version
- `NAMESPACE` — Kubernetes namespace for the deployment

When bumping a version, update it in every code block and any values files within the same guide. Check `guides/prereq/` for shared version pins that may also need updating.
