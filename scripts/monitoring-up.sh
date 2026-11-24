#!/usr/bin/env bash
# Instala Prometheus + Grafana (kube-prometheus-stack) en el clúster y
# carga el dashboard de NEXO (grafana/dashboard.json).
#
# Uso: scripts/monitoring-up.sh
# Variables: MONITORING_NAMESPACE (monitoring), MONITORING_RELEASE (monitoring)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
RELEASE="${MONITORING_RELEASE:-monitoring}"
CHART_VERSION="93.9.0"

echo "[1/5] Repositorio Helm prometheus-community..."
helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null

echo "[2/5] Namespace ${NAMESPACE}..."
kubectl create namespace "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "[3/5] Secret con las credenciales de Grafana..."
if kubectl get secret grafana-admin -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "      Ya existe, se reutiliza."
else
    kubectl create secret generic grafana-admin \
        --namespace "$NAMESPACE" \
        --from-literal=admin-user=admin \
        --from-literal=admin-password="$(openssl rand -hex 16)"
fi

echo "[4/5] kube-prometheus-stack ${CHART_VERSION} (puede tardar unos minutos)..."
helm upgrade --install "$RELEASE" prometheus-community/kube-prometheus-stack \
    --namespace "$NAMESPACE" \
    --version "$CHART_VERSION" \
    -f "$ROOT_DIR/monitoring/kube-prometheus-stack-values.yaml" \
    --wait \
    --timeout 10m

echo "[5/5] Dashboard de NEXO..."
kubectl create configmap nexo-grafana-dashboard \
    --namespace "$NAMESPACE" \
    --from-file=nexo-dashboard.json="$ROOT_DIR/grafana/dashboard.json" \
    --dry-run=client -o yaml \
  | kubectl label --local -f - grafana_dashboard=1 -o yaml \
  | kubectl apply -f -

cat <<INFO

Monitorización lista.

  Si NEXO ya estaba desplegado, vuelve a desplegarlo para que Helm cree el
  ServiceMonitor (solo se crea si existe la CRD que acabamos de instalar):
    helm upgrade --install nexo ./helm-chart -n nexo -f helm-chart/values-dev.yaml

  Grafana:     kubectl port-forward -n ${NAMESPACE} svc/${RELEASE}-grafana 3000:80
               http://localhost:3000  (usuario: admin)
  Contraseña:  kubectl get secret grafana-admin -n ${NAMESPACE} \\
                 -o jsonpath='{.data.admin-password}' | base64 -d; echo
  Prometheus:  kubectl port-forward -n ${NAMESPACE} svc/${RELEASE}-kube-prometheus-prometheus 9090:9090
               http://localhost:9090/targets  (buscar serviceMonitor/nexo/nexo-api)
INFO
