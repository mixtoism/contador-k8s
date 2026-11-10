#!/usr/bin/env bash
# Vuelca el estado del clúster (para cuando algo falla).
source "$(dirname "$0")/comun.sh"
k() { $MOTOR exec "$CLUSTER" kubectl "$@" || true; }
k get pods -A -o wide
k describe pods -A -l app.kubernetes.io/part-of=contador | tail -60
k logs -A -l app=contador --tail=30 --prefix
k get events -A --sort-by=.lastTimestamp | tail -40
$MOTOR exec "$CLUSTER" crictl images || true
