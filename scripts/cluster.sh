#!/usr/bin/env bash
# Clúster Kubernetes de un nodo (k3s) dentro de un contenedor.
# Los NodePort 30080-30085 se publican en localhost:8080-8085:
#   terraform dev/prod → 8080/8081 · kubectl dev/prod → 8082/8083 · helm dev/prod → 8084/8085
#   scripts/cluster.sh crear | borrar | cargar <tag>
set -euo pipefail
source "$(dirname "$0")/comun.sh"

case "${1:-}" in
  crear)
    $MOTOR run -d --name "$CLUSTER" --privileged \
      -p 127.0.0.1:6443:6443 -p 8080-8085:30080-30085 \
      "$K3S_IMAGEN" server --disable=traefik --disable=metrics-server --tls-san=127.0.0.1
    echo -n "Esperando al clúster"
    until $MOTOR exec "$CLUSTER" kubectl get nodes 2>/dev/null | grep -q ' Ready'; do
      $MOTOR container inspect -f '{{.State.Running}}' "$CLUSTER" | grep -q true \
        || { echo; $MOTOR logs --tail 20 "$CLUSTER"; exit 1; }
      echo -n .; sleep 2
    done
    $MOTOR exec "$CLUSTER" cat /etc/rancher/k3s/k3s.yaml > "$RAIZ/kubeconfig"
    chmod 600 "$RAIZ/kubeconfig"
    echo " listo. export KUBECONFIG=$RAIZ/kubeconfig"
    ;;
  borrar)
    $MOTOR rm -f "$CLUSTER"
    rm -f "$RAIZ/kubeconfig"
    ;;
  cargar)
    # Construye la imagen y la mete en el containerd del clúster (sin registro).
    tag=${2:-v1}
    $MOTOR build -t "$APP_IMAGEN:$tag" "$RAIZ/app"
    $MOTOR save "$APP_IMAGEN:$tag" | $MOTOR exec -i "$CLUSTER" ctr -n k8s.io images import -
    ;;
  *)
    echo "uso: $0 crear | borrar | cargar <tag>" >&2; exit 2 ;;
esac
