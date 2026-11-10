# Variables compartidas por los scripts. Todo corre en contenedores:
#   MOTOR=podman (por defecto) | "sudo podman" | docker
MOTOR=${MOTOR:-podman}
CLUSTER=contador-k3s
K3S_IMAGEN=docker.io/rancher/k3s:v1.31.4-k3s1
TF_IMAGEN=docker.io/hashicorp/terraform:1.9.8
APP_IMAGEN=localhost/contador
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
HELM_IMAGEN=docker.io/alpine/helm:3.16.2
