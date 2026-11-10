#!/usr/bin/env bash
# Terraform en contenedor.
#   scripts/tf.sh <dev|prod> <comando> [args...]   clúster local, un workspace por entorno
#   scripts/tf.sh aws <comando> [args...]          terraform/aws (p. ej. "test", todo mock)
set -euo pipefail
source "$(dirname "$0")/comun.sh"

destino=${1:?uso: $0 <dev|prod|aws> <comando> [args...]}; shift
cmd=${1:?falta el comando de terraform}; shift

dir=/w/terraform extra=() vars=()
if [ "$destino" = aws ]; then
  dir=/w/terraform/aws
else
  vars=(-e TF_WORKSPACE="$destino")
  case "$cmd" in plan|apply|destroy) extra=(-var-file="$destino.tfvars") ;; esac
fi

tty=(); [ -t 0 ] && [ -t 1 ] && tty=(-it)
# --network host: el contenedor llega al API server en 127.0.0.1:6443.
exec $MOTOR run --rm "${tty[@]}" --network host --security-opt label=disable \
  -v "$RAIZ:/w" -w "$dir" "${vars[@]}" -e TF_IN_AUTOMATION \
  "$TF_IMAGEN" "$cmd" "${extra[@]}" "$@"
