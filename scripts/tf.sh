#!/usr/bin/env bash
# Terraform en contenedor. Cada entorno es un workspace con su .tfvars:
#   scripts/tf.sh dev-kube|prod-kube <comando>              terraform/      (clúster k3s local)
#   scripts/tf.sh dev-lambda|prod-lambda <comando>          terraform/aws/  (AWS de verdad)
#   scripts/tf.sh dev-beanstalk|prod-beanstalk <comando>    terraform/aws/  (AWS de verdad)
# Sin entorno, para fmt, validate y test (mock):
#   scripts/tf.sh kube|aws <comando>
set -euo pipefail
source "$(dirname "$0")/comun.sh"

destino=${1:?uso: $0 <entorno|kube|aws> <comando> [args...]}; shift
cmd=${1:?falta el comando de terraform}; shift

case "$destino" in
  kube) dir=/w/terraform ;;
  aws) dir=/w/terraform/aws ;;
  dev-kube|prod-kube) dir=/w/terraform ;;
  dev-lambda|prod-lambda|dev-beanstalk|prod-beanstalk) dir=/w/terraform/aws ;;
  *) echo "Entorno desconocido: $destino" >&2; exit 1 ;;
esac

vars=() extra=()
if [[ "$destino" == *-* ]]; then
  vars=(-e TF_WORKSPACE="$destino")
  case "$cmd" in plan|apply|destroy) extra=(-var-file="$destino.tfvars") ;; esac
fi

if [ "$dir" = /w/terraform/aws ]; then
  # Despliegue real: credenciales temporales desde el CLI de aws. Valen para cualquier
  # forma de iniciar sesión (aws login, SSO, perfiles…), la entienda o no el proveedor.
  if [[ "$destino" == *-* ]] && [ -z "${AWS_ACCESS_KEY_ID:-}" ] && command -v aws >/dev/null; then
    if ! cred=$(aws configure export-credentials --format env); then
      echo "No hay sesión de AWS válida: ejecuta 'aws login' (o 'aws sso login')." >&2
      exit 1
    fi
    eval "$cred"
    export AWS_REGION=${AWS_REGION:-$(aws configure get region || echo eu-west-1)}
  fi
  for v in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION; do
    if [ -n "${!v:-}" ]; then vars+=(-e "$v"); fi
  done
  if [ -d "$HOME/.aws" ]; then vars+=(-v "$HOME/.aws:/root/.aws:ro"); fi
fi

tty=(); [ -t 0 ] && [ -t 1 ] && tty=(-it)
# --network host: el contenedor llega al API server en 127.0.0.1:6443.
exec $MOTOR run --rm "${tty[@]}" --network host --security-opt label=disable \
  -v "$RAIZ:/w" -w "$dir" "${vars[@]}" -e TF_IN_AUTOMATION \
  "$TF_IMAGEN" "$cmd" "${extra[@]}" "$@"
