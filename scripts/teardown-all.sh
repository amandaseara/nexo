#!/usr/bin/env bash
# Borra todos los recursos creados por setup-all.sh.
# Uso: scripts/teardown-all.sh [--stop-cluster | --delete-cluster]
#   (sin opciones) borra NEXO, monitorización, Kyverno y Falco del clúster
#   --stop-cluster   además para Minikube y Jenkins
#   --delete-cluster además elimina el clúster de Minikube
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[1/5] Port-forwards..."
"$DIR/port-forward.sh" stop

echo "[2/5] NEXO..."
helm uninstall nexo -n nexo --ignore-not-found --wait 2>/dev/null
kubectl delete namespace nexo --ignore-not-found --wait=true

echo "[3/5] Kyverno y Falco..."
kubectl delete -f "$DIR/../k8s/kyverno/policies/" --ignore-not-found
helm uninstall kyverno -n kyverno --ignore-not-found --wait 2>/dev/null
helm uninstall falco -n falco --ignore-not-found --wait 2>/dev/null
kubectl delete namespace kyverno falco --ignore-not-found

echo "[4/5] Monitorización..."
"$DIR/monitoring-down.sh" --purge-crds

echo "[5/5] Clúster..."
case "${1:-}" in
    --stop-cluster)   minikube stop; brew services stop jenkins-lts ;;
    --delete-cluster) minikube delete; brew services stop jenkins-lts ;;
    *) echo "      Minikube sigue en marcha (usa --stop-cluster o --delete-cluster)." ;;
esac

echo "Recursos eliminados."
