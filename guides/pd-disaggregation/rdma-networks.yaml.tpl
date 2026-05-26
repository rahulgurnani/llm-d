# Go template — render before applying to a cluster:
#   gomplate -f rdma-networks.yaml.tpl > rdma-networks.yaml
#
# To use a non-default VPC or subnet, set the vpc/vpcSubnet fields below
# before rendering. All 8 GKENetworkParamSet objects share the same VPC
# and subnet; adjust per-network if your topology requires separate subnets.
{{ range $i := until 8 }}
apiVersion: networking.gke.io/v1
kind: GKENetworkParamSet
metadata:
  name: rdma-{{ $i }}
spec:
  vpc: default      # replace with your VPC name if not using the default VPC
  vpcSubnet: default # replace with your subnet name
  deviceMode: NetDevice
---
apiVersion: networking.gke.io/v1
kind: Network
metadata:
  name: rdma-{{ $i }}
spec:
  parametersRef:
    group: networking.gke.io
    kind: GKENetworkParamSet
    name: rdma-{{ $i }}
  type: Device
---
{{ end }}
