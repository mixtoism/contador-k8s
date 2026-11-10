#!/usr/bin/env bash
# Helm en contenedor, con el kubeconfig del clúster local.
#   scripts/helm.sh lint helm/contador
#   scripts/helm.sh upgrade --install contador helm/contador -n contador-helm-dev --create-namespace -f helm/contador/values-dev.yaml
set -euo pipefail
source "$(dirname "$0")/comun.sh"

tty=(); [ -t 0 ] && [ -t 1 ] && tty=(-it)
exec $MOTOR run --rm "${tty[@]}" --network host --security-opt label=disable \
  -v "$RAIZ:/w" -w /w -e KUBECONFIG=/w/kubeconfig -e HELM_CACHE_HOME=/tmp/helm \
  "$HELM_IMAGEN" "$@"
