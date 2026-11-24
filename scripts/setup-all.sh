#!/usr/bin/env bash
# Levanta TODO el entorno de NEXO desde cero:
#   1. Docker, Minikube y Jenkins            (start-tools.sh)
#   2. Operadores: Prometheus Operator + Grafana (monitoring-up.sh),
#      Kyverno y Falco (si están sus scripts)
#   3. NEXO con Helm                          (deploy-local.sh)
#   4. Port-forwards y tráfico de ejemplo
#
# Uso: scripts/setup-all.sh [--no-traffic]
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
cd "$ROOT"

step() { echo; echo "=================== $* ==================="; }

for tool in docker minikube kubectl helm curl openssl; do
    command -v "$tool" >/dev/null || { echo "Falta '$tool' en el PATH" >&2; exit 1; }
done

step "1. Herramientas base"
"$DIR/start-tools.sh"

step "2. Monitorización (Prometheus + Grafana)"
"$DIR/monitoring-up.sh"

# Kyverno y Falco: scripts propios del equipo, si existen.
for comp in kyverno falco; do
    for s in "$DIR/$comp-up.sh" "$DIR/install-$comp.sh" "$DIR/$comp/install.sh"; do
        if [[ -x $s ]]; then
            step "2. $comp"
            "$s"
            break
        fi
    done
done

step "3. Despliegue de NEXO"
"$DIR/deploy-local.sh"

step "4. Accesos"
"$DIR/port-forward.sh" start
sleep 3

if [[ "${1:-}" != "--no-traffic" ]]; then
    step "5. Tráfico de ejemplo (60 s) para poblar Grafana"
    "$DIR/generate-traffic.sh" http://localhost:8000 60
fi

PASS=$(kubectl get secret grafana-admin -n monitoring \
    -o jsonpath='{.data.admin-password}' | base64 -d)

cat <<INFO

Entorno listo.
  API (Swagger)  http://localhost:8000/docs
  Métricas       http://localhost:8000/metrics
  Grafana        http://localhost:3000   admin / ${PASS}
                 Dashboard: "NEXO - Visión general"
  Prometheus     http://localhost:9090/targets
  Jenkins        http://localhost:8080

  Más tráfico:   scripts/generate-traffic.sh http://localhost:8000 300
  Borrar todo:   scripts/teardown-all.sh
INFO
