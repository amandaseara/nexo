#!/usr/bin/env bash
# Elimina Prometheus + Grafana del clúster.
# Uso: scripts/monitoring-down.sh [--purge-crds]
set -euo pipefail

NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
RELEASE="${MONITORING_RELEASE:-monitoring}"

helm uninstall "$RELEASE" -n "$NAMESPACE" --ignore-not-found
kubectl delete namespace "$NAMESPACE" --ignore-not-found

# Helm no borra las CRDs del operador al desinstalar.
if [[ "${1:-}" == "--purge-crds" ]]; then
    kubectl get crd -o name | grep 'monitoring.coreos.com' \
        | xargs -r kubectl delete
fi

echo "Monitorización eliminada."
