# PD-Disaggregation on GKE

This guide provides specific instructions for deploying PD-disaggregation with RDMA (RoCE) on GKE. For the puposes of this guide, we will be using NVIDIA H200 GPUs on A3 Ultra. **Note**: This is picked from [official GCP page](https://docs.cloud.google.com/ai-hypercomputer/docs/create/gke-ai-hypercompute-custom). Follow the official GCP guide for latest updates and detailed instructions.

## Prerequisites

1.  A GKE cluster in a region where A3 Ultra is available (e.g., `us-south1` or `us-central1`). Lets take `us-south1` for this guide.
2.  The following environment variables set:
    ```bash
    export PROJECT_ID="your-project-id"
    export REGION="us-south1"
    export ZONE="us-south1-b"
    export GVNIC_NETWORK_PREFIX="a3ultra-gvnic"
    export RDMA_NETWORK_PREFIX="a3ultra-rdma"
    export CLUSTER_NAME="a3-ultra-cluster"
    ```

## 1. Setup Networking Infrastructure

A3 Ultra requires multiple NICs: one for the Titanium CPU NIC (GVNIC) and eight for GPU-to-GPU RDMA (RoCE).

### Create GVNIC VPC
```bash
gcloud compute networks create ${GVNIC_NETWORK_PREFIX}-net --subnet-mode=custom

gcloud compute networks subnets create ${GVNIC_NETWORK_PREFIX}-sub \
    --network=${GVNIC_NETWORK_PREFIX}-net \
    --region=${REGION} \
    --range=192.168.0.0/24

gcloud compute firewall-rules create ${GVNIC_NETWORK_PREFIX}-internal \
    --network=${GVNIC_NETWORK_PREFIX}-net \
    --action=ALLOW \
    --rules=tcp:0-65535,udp:0-65535,icmp \
    --source-ranges=192.168.0.0/16
```

### Create HPC (RDMA) VPC
```bash
gcloud beta compute networks create ${RDMA_NETWORK_PREFIX}-net \
    --network-profile=${ZONE}-vpc-roce \
    --subnet-mode=custom

for N in {0..7}; do
  gcloud compute networks subnets create ${RDMA_NETWORK_PREFIX}-sub-$N \
    --network=${RDMA_NETWORK_PREFIX}-net \
    --region=${REGION} \
    --range=192.168.$((N+1)).0/24
done
```

## 2. Create the Node Pool

Provision the H200 node pool with the additional network interfaces. Spot instances are recommended for availability in some regions.

```bash
gcloud container node-pools create h200 \
    --region=${REGION} \
    --cluster=${CLUSTER_NAME} \
    --node-locations=${ZONE} \
    --machine-type=a3-ultragpu-8g \
    --accelerator=type=nvidia-h200-141gb,count=8,gpu-driver-version=latest \
    --enable-autoscaling \
    --min-nodes=0 \
    --max-nodes=8 \
    --location-policy=ANY \
    --spot \
    --additional-node-network network=${GVNIC_NETWORK_PREFIX}-net,subnetwork=${GVNIC_NETWORK_PREFIX}-sub \
    --additional-node-network network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-0 \
    --additional-node-network network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-1 \
    --additional-node-network network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-2 \
    --additional-node-network network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-3 \
    --additional-node-network network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-4 \
    --additional-node-network network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-5 \
    --additional-node-network network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-6 \
    --additional-node-network network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-7
```

## 3. Apply Kubernetes Network Config

Apply the `Network` and `GKENetworkParamSet` resources to expose the RDMA interfaces to Kubernetes. This step uses `envsubst` to inject your `RDMA_NETWORK_PREFIX` into the configuration.

```bash
envsubst < guides/pd-disaggregation/rdma-networks.yaml | kubectl apply -f -
```

## 4. Deploy the Model Server

Deploy SGLang with the GKE overlay. Note that the GKE overlay uses `privileged: true` for RDMA, which bypasses GPU isolation. To ensure stability for large models (120B+):

1.  Each pod (prefill and decode) requests **8 GPUs** to ensure it has a dedicated node.
2.  **Tensor Parallel (TP)** is set to **8** to utilize the full node memory.
3.  **Pod Anti-Affinity** is configured to keep roles separated.

```bash
kubectl apply -n ${NAMESPACE} -k guides/pd-disaggregation/modelserver/gpu/sglang/gke/
```

## Verification & Logs

Monitor the startup as the 120B model takes significant time to load weights:

```bash
kubectl get pods -n ${NAMESPACE} -w
kubectl logs -n ${NAMESPACE} -l llm-d.ai/role=decode -c modelserver --tail=100
```
