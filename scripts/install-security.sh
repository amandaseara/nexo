#!/usr/bin/env bash
# Instala Kyverno y Falco con sus Helm charts oficiales y aplica las políticas de NEXO.
# Es idempotente: se puede correr de nuevo sin romper nada.
set -euo pipefail

KYVERNO_CHART_VERSION="3.10.0"   # Kyverno v1.20
FALCO_CHART_VERSION="9.2.2"      # Falco 0.45

echo "[1/4] Agregando repos de Helm..."
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1 || true
helm repo update kyverno falcosecurity >/dev/null

echo "[2/4] Instalando Kyverno..."
helm upgrade --install kyverno kyverno/kyverno \
    --version "${KYVERNO_CHART_VERSION}" \
    --namespace kyverno --create-namespace \
    --wait --timeout 5m

echo "[3/4] Instalando Falco (driver modern_ebpf)..."
helm upgrade --install falco falcosecurity/falco \
    --version "${FALCO_CHART_VERSION}" \
    --namespace falco --create-namespace \
    --set driver.kind=modern_ebpf \
    --set tty=true \
    --set falcosidekick.enabled=false \
    --wait --timeout 5m

echo "[4/4] Aplicando políticas de Kyverno..."
kubectl create namespace nexo --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f k8s/kyverno/policies/
sleep 5

echo ""
kubectl get validatingpolicy
echo ""
echo "Listo. Siguiente paso: ./scripts/validate-kyverno.sh y ./scripts/trigger-falco.sh"
