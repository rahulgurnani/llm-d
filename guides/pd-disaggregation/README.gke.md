# PD-Disaggregation on GKE

This guide provides specific instructions for deploying PD-disaggregation with RDMA (RoCE) on GKE. For the purposes of this guide, we will be using NVIDIA H200 GPUs on A3 Ultra. **Note**: This is picked from [official GCP page](https://docs.cloud.google.com/ai-hypercomputer/docs/create/gke-ai-hypercompute-custom). Follow the official GCP guide for latest updates and detailed instructions.

## Prerequisites

Before deploying, follow the [official GKE AI Hypercompute guide](https://docs.cloud.google.com/ai-hypercomputer/docs/create/gke-ai-hypercompute-custom) to complete the following steps:

1. Create VPCs and subnets (GVNIC + 8 RDMA networks)
2. Create the GKE cluster and A3 Ultra node pool with multi-networking enabled
3. Apply the `GKENetworkParamSet` and `Network` Kubernetes resources, and install RDMA binaries via DaemonSet

Once your cluster is ready, set the following environment variables:

```bash
export NAMESPACE="default"
```

## 1. Deploy the Model Server

Deploy SGLang with the GKE overlay. Note that the GKE overlay uses `privileged: true` for RDMA, which bypasses GPU isolation. To ensure stability for large models (120B+):

1.  Each pod (prefill and decode) requests **8 GPUs** to ensure it has a dedicated node.
2.  **Tensor Parallel (TP)** is set to **8** to utilize the full node memory.
3.  **Pod Anti-Affinity** is configured to keep roles separated.

```bash
kubectl apply -n ${NAMESPACE} -k guides/pd-disaggregation/modelserver/gpu/sglang/gke/
```

## 2. Verification & Logs

Monitor the startup as the 120B model takes significant time to load weights:

```bash
kubectl get pods -n ${NAMESPACE} -w
kubectl logs -n ${NAMESPACE} -l llm-d.ai/role=decode -c modelserver --tail=100
```
