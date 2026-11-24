#!/usr/bin/env bash
# Abre (o cierra) los port-forward para la demo:
#   API        http://localhost:8000   (Swagger en /docs, métricas en /metrics)
#   Grafana    http://localhost:3000
#   Prometheus http://localhost:9090
# Uso: scripts/port-forward.sh [start|stop|status]
set -euo pipefail

PID_DIR="${TMPDIR:-/tmp}/nexo-port-forward"
mkdir -p "$PID_DIR"

forward() {  # nombre namespace recurso puertos
    local name=$1 ns=$2 target=$3 ports=$4
    if ! kubectl get -n "$ns" "$target" >/dev/null 2>&1; then
        echo "  - $name: $target no existe en $ns, se omite"
        return
    fi
    nohup kubectl port-forward -n "$ns" "$target" "$ports" \
        > "$PID_DIR/$name.log" 2>&1 &
    echo $! > "$PID_DIR/$name.pid"
    echo "  - $name: http://localhost:${ports%%:*}"
}

stop() {
    for f in "$PID_DIR"/*.pid; do
        [[ -e $f ]] || continue
        kill "$(cat "$f")" 2>/dev/null || true
        rm -f "$f"
    done
}

case "${1:-start}" in
    start)
        stop
        echo "Abriendo port-forwards..."
        forward api        nexo       svc/nexo-api                             8000:8000
        forward grafana    monitoring svc/monitoring-grafana                   3000:80
        forward prometheus monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
        ;;
    stop)
        stop
        echo "Port-forwards cerrados."
        ;;
    status)
        for f in "$PID_DIR"/*.pid; do
            [[ -e $f ]] || continue
            n=$(basename "$f" .pid)
            kill -0 "$(cat "$f")" 2>/dev/null && echo "$n: activo" || echo "$n: caído"
        done
        ;;
    *) echo "Uso: $0 [start|stop|status]" >&2; exit 1 ;;
esac
