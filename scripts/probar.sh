#!/usr/bin/env bash
# Lanza N peticiones y cuenta qué pod atendió cada una.
#   scripts/probar.sh <url> [N]   → tabla Markdown por la salida estándar
set -euo pipefail
url=${1:?uso: $0 <url> [N]}; n=${2:-30}

for _ in $(seq 60); do curl -fs "$url/readyz" >/dev/null && break; sleep 1; done

respuestas=$(for _ in $(seq "$n"); do curl -fs "$url/api"; done)
version=$(jq -r .version <<<"$respuestas" | sort -u | paste -sd,)
total=$(jq -s 'map(.visitas) | max' <<<"$respuestas")

echo "| Pod | Peticiones |"
echo "|---|---|"
jq -r .pod <<<"$respuestas" | sort | uniq -c | sort -rn | awk '{print "| `" $2 "` | " $1 " |"}'
echo
echo "Versión: **$version** · contador total: **$total**"
