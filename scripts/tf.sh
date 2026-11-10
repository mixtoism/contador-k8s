#!/usr/bin/env bash
# Terraform en contenedor, con un workspace por entorno.
#   scripts/tf.sh <dev|prod> <comando terraform> [args...]
#   p. ej.: scripts/tf.sh dev apply -var replicas=3
set -euo pipefail
source "$(dirname "$0")/comun.sh"

entorno=${1:?uso: $0 <dev|prod> <comando> [args...]}; shift
cmd=${1:?falta el comando de terraform}; shift

extra=()
case "$cmd" in plan|apply|destroy) extra=(-var-file="$entorno.tfvars") ;; esac

tty=(); [ -t 0 ] && [ -t 1 ] && tty=(-it)
# --network host: el contenedor llega al API server en 127.0.0.1:6443.
exec $MOTOR run --rm "${tty[@]}" --network host --security-opt label=disable \
  -v "$RAIZ:/w" -w /w/terraform -e TF_WORKSPACE="$entorno" -e TF_IN_AUTOMATION \
  "$TF_IMAGEN" "$cmd" "${extra[@]}" "$@"
