#!/usr/bin/env bash
# Terraform en contenedor.
#   scripts/tf.sh <dev|prod> <comando> [args...]   clúster local, un workspace por entorno
#   scripts/tf.sh aws <comando> [args...]          terraform/aws sin entorno: init, validate, test (mock)
#   scripts/tf.sh <aws-dev|aws-prod> <comando>      terraform/aws de verdad, un workspace por entorno
set -euo pipefail
source "$(dirname "$0")/comun.sh"

destino=${1:?uso: $0 <dev|prod|aws|aws-dev|aws-prod> <comando> [args...]}; shift
cmd=${1:?falta el comando de terraform}; shift

dir=/w/terraform extra=() vars=()
if [[ "$destino" == aws* ]]; then
  dir=/w/terraform/aws
  entorno=${destino#aws-}
  if [ "$entorno" != aws ]; then
    vars=(-e TF_WORKSPACE="$entorno")
    case "$cmd" in plan|apply|destroy) extra=(-var-file="$entorno.tfvars") ;; esac
    # Credenciales temporales desde el CLI de aws: valen para cualquier forma de
    # iniciar sesión (aws login, SSO, perfiles…), las entienda o no el proveedor.
    if [ -z "${AWS_ACCESS_KEY_ID:-}" ] && command -v aws >/dev/null; then
      eval "$(aws configure export-credentials --format env)" ||
        { echo "No hay sesión de AWS: ejecuta 'aws login' (o 'aws sso login')." >&2; exit 1; }
      export AWS_REGION=${AWS_REGION:-$(aws configure get region || echo eu-west-1)}
    fi
  fi
  # Pasa las credenciales de AWS si existen.
  for v in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION; do
    if [ -n "${!v:-}" ]; then vars+=(-e "$v"); fi
  done
  [ -d "$HOME/.aws" ] && vars+=(-v "$HOME/.aws:/root/.aws:ro")
else
  vars=(-e TF_WORKSPACE="$destino")
  case "$cmd" in plan|apply|destroy) extra=(-var-file="$destino.tfvars") ;; esac
fi

tty=(); [ -t 0 ] && [ -t 1 ] && tty=(-it)
# --network host: el contenedor llega al API server en 127.0.0.1:6443.
exec $MOTOR run --rm "${tty[@]}" --network host --security-opt label=disable \
  -v "$RAIZ:/w" -w "$dir" "${vars[@]}" -e TF_IN_AUTOMATION \
  "$TF_IMAGEN" "$cmd" "${extra[@]}" "$@"
