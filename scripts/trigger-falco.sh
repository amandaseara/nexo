#!/usr/bin/env bash
# Dispara una alerta de Falco buscando claves SSH desde un pod y guarda la alerta
# en reports/falco-event.log, con una descripción del evento.
set -euo pipefail

LOG="reports/falco-event.log"
mkdir -p reports

echo "[1/4] Preparando namespace nexo..."
kubectl create namespace nexo --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl delete pod falco-test -n nexo --ignore-not-found >/dev/null

echo "[2/4] Lanzando el pod que busca claves privadas (find /etc /home -name id_rsa)..."
kubectl apply -f k8s/falco/falco-test-pod.yaml
kubectl wait pod/falco-test -n nexo \
    --for=jsonpath='{.status.phase}'=Succeeded --timeout=120s

echo "[3/4] Esperando a que Falco procese el evento..."
sleep 10

echo "[4/4] Buscando la alerta en los logs de Falco..."
alerts=$(kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --since=2m --tail=-1 \
    | grep "private keys or passwords" | grep "id_rsa" || true)

if [ -z "$alerts" ]; then
    echo "ERROR: Falco no registró la alerta. Revisá: kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco"
    exit 1
fi

{
    echo "=== Evento de Falco: $(date '+%Y-%m-%d %H:%M:%S %z') ==="
    echo ""
    echo "Acción ejecutada:"
    echo "  kubectl apply -f k8s/falco/falco-test-pod.yaml"
    echo "  (pod busybox:1.36 en el namespace nexo que ejecuta: find /etc /home -name id_rsa)"
    echo ""
    echo "Descripción:"
    echo "  Un proceso dentro de un contenedor recorre /etc y /home buscando claves"
    echo "  privadas SSH (id_rsa). Es lo que hace un atacante después de entrar: buscar"
    echo "  credenciales para saltar a otros sistemas. Falco ve la syscall execve() del"
    echo "  proceso 'find' con su driver eBPF y dispara la regla por defecto"
    echo "  'Search Private Keys or Passwords' (prioridad Warning)."
    echo ""
    echo "  El pod cumple las 4 políticas de Kyverno (tag fijo, no root, límites), así que"
    echo "  Kyverno lo admitió. Kyverno controla CÓMO está configurado un pod antes de entrar;"
    echo "  Falco vigila QUÉ HACE una vez que corre. Falco detecta y avisa: no bloquea,"
    echo "  el pod terminó normalmente."
    echo ""
    echo "Alerta registrada por Falco:"
    echo "$alerts"
} > "$LOG"

kubectl delete pod falco-test -n nexo --ignore-not-found >/dev/null

echo ""
echo "Alerta capturada en $LOG:"
echo "$alerts"
