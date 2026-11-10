#!/usr/bin/env bash
# OpenTofu en contenedor, siempre sobre tofu/ (un solo OpenTofu para todo).
#
#   scripts/tofu.sh <entorno> <comando> [args]   entorno = dev|prod - kube|beanstalk|lambda
#   scripts/tofu.sh <comando> [args]             sin entorno: fmt, validate, test (mock)…
#
# Con entorno, cada uno es un workspace (estado propio) y a plan/apply/destroy se les
# pasa entornos/<entorno>.tfvars, donde está plataforma = "...". Equivale a:
#   tofu workspace select dev-beanstalk
#   tofu apply -var-file=entornos/dev-beanstalk.tfvars
set -euo pipefail
source "$(dirname "$0")/comun.sh"

entorno=""
case "${1:?uso: $0 [entorno] <comando> [args...]}" in
  *-kube|*-beanstalk|*-lambda) entorno=$1; shift ;;
esac
cmd=${1:?falta el comando de tofu}; shift

vars=() extra=()
if [ -n "$entorno" ]; then
  if [ ! -f "$RAIZ/tofu/entornos/$entorno.tfvars" ]; then
    echo "Entorno desconocido: $entorno (mira tofu/entornos/)" >&2; exit 1
  fi
  vars=(-e TF_WORKSPACE="$entorno")
  case "$cmd" in plan|apply|destroy) extra=(-var-file="entornos/$entorno.tfvars") ;; esac
fi

if [[ "$entorno" == *-beanstalk || "$entorno" == *-lambda ]]; then
  # Despliegue real en AWS: credenciales temporales desde el CLI de aws. Valen para
  # cualquier forma de iniciar sesión (aws login, SSO, perfiles…).
  if [ -z "${AWS_ACCESS_KEY_ID:-}" ] && command -v aws >/dev/null; then
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
  if [ -n "${AWS_REGION:-}" ] && [ ${#extra[@]} -gt 0 ]; then extra+=(-var region="$AWS_REGION"); fi
fi

tty=(); [ -t 0 ] && [ -t 1 ] && tty=(-it)
# --network host: el contenedor llega al API server en 127.0.0.1:6443.
exec $MOTOR run --rm "${tty[@]}" --network host --security-opt label=disable \
  -v "$RAIZ:/w" -w /w/tofu "${vars[@]}" -e TF_IN_AUTOMATION \
  "$TOFU_IMAGEN" "$cmd" "${extra[@]}" "$@"
