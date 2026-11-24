#!/usr/bin/env bash
# Abre todo lo necesario para la demo: comprueba el clúster, abre los
# port-forward y abre en el navegador la API, Grafana, Prometheus y Jenkins.
# Uso: scripts/open-demo.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! kubectl get nodes >/dev/null 2>&1; then
    echo "El clúster no responde: arrancando Docker, Minikube y Jenkins..."
    "$DIR/start-tools.sh"
fi
brew services start jenkins-lts >/dev/null 2>&1 || true

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
