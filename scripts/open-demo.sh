#!/usr/bin/env bash
# Deja la demo lista y la abre:
#   - arranca Docker, Minikube y Jenkins si están parados
#   - instala lo que falte en el clúster (monitorización, Kyverno/Falco, NEXO)
#   - abre los port-forward y las pestañas de la API, Grafana, Prometheus y Jenkins
# Uso: scripts/open-demo.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! kubectl get nodes >/dev/null 2>&1; then
    echo "El clúster no responde: arrancando Docker, Minikube y Jenkins..."
    "$DIR/start-tools.sh"
fi
brew services start jenkins-lts >/dev/null 2>&1 || true

ROOT="$(cd "$DIR/.." && pwd)"
cd "$ROOT"

installed() {  # release namespace
    helm status "$1" -n "$2" >/dev/null 2>&1
}

if installed monitoring monitoring; then
    echo "[OK] Prometheus + Grafana"
else
    echo "[..] Falta Prometheus + Grafana: instalando..."
    "$DIR/monitoring-up.sh"
fi

if installed kyverno kyverno && installed falco falco \
   && [[ $(kubectl get validatingpolicy --no-headers 2>/dev/null | wc -l) -ge 4 ]]; then
    echo "[OK] Kyverno (4 políticas) + Falco"
else
    echo "[..] Falta Kyverno, Falco o las políticas: instalando..."
    "$DIR/install-security.sh"
fi

if installed nexo nexo; then
    echo "[OK] NEXO"
else
    echo "[..] Falta NEXO: desplegando..."
    "$DIR/deploy-local.sh"
fi

echo "Esperando a que la API esté lista..."
kubectl rollout status deployment/nexo-api -n nexo --timeout=180s

"$DIR/port-forward.sh" start
sleep 3

echo
echo "Estado de la API: $(curl -s localhost:8000/health/ready || echo 'no responde')"

PASS=$(kubectl get secret grafana-admin -n monitoring \
    -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || true)

open "http://localhost:8000/docs"
open "http://localhost:3000/d/nexo-overview"
open "http://localhost:9090/targets"
open "http://127.0.0.1:8080/job/nexo/"

cat <<INFO

Abierto en el navegador:
  API (Swagger)  http://localhost:8000/docs
  Grafana        http://localhost:3000/d/nexo-overview   admin / ${PASS}
  Prometheus     http://localhost:9090/targets
  Jenkins        http://127.0.0.1:8080/job/nexo/          admin / admin

Para llenar Grafana:  ./scripts/generate-traffic.sh http://localhost:8000 300
INFO
