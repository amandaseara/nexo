#!/usr/bin/env bash
# Prueba las políticas de Kyverno y guarda la evidencia en reports/kyverno-validation.log.
# Cada manifiesto de k8s/kyverno/tests/ rompe una sola política (o ninguna, el "good").
# Además valida que el chart de NEXO cumpla las 4 políticas (dry-run en el servidor).
set -uo pipefail

LOG="reports/kyverno-validation.log"
mkdir -p reports
kubectl create namespace nexo --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Borra restos de corridas anteriores
kubectl delete -f k8s/kyverno/tests/ --ignore-not-found >/dev/null 2>&1

PASSED=0
FAILED=0

{
    echo "=== Validación de políticas Kyverno: $(date '+%Y-%m-%d %H:%M:%S %z') ==="
    echo ""
    echo "--- Políticas instaladas ---"
    kubectl get validatingpolicy disallow-latest-tag require-requests-limits require-run-as-non-root require-probes 2>/dev/null
    echo ""
} > "$LOG"

for file in k8s/kyverno/tests/*.yaml; do
    name=$(basename "$file")
    expected="RECHAZADO"
    [[ "$name" == 00-good* ]] && expected="ADMITIDO"

    output=$(kubectl apply -f "$file" 2>&1)
    if [ $? -eq 0 ]; then result="ADMITIDO"; else result="RECHAZADO"; fi

    if [ "$result" == "$expected" ]; then status="OK"; PASSED=$((PASSED+1)); else status="ERROR"; FAILED=$((FAILED+1)); fi

    {
        echo "--- $name ---"
        echo "# $(head -1 "$file" | sed 's/^# //')"
        echo "\$ kubectl apply -f $file"
        echo "$output"
        echo "Esperado: $expected | Resultado: $result | $status"
        echo ""
    } >> "$LOG"
    echo "[$status] $name -> $result"
done

{
    echo "--- Chart de NEXO (helm template + kubectl apply --dry-run=server) ---"
    echo "El dry-run en el servidor pasa por el webhook de Kyverno sin crear nada."
} >> "$LOG"
# Release con otro nombre: si NEXO ya está desplegado, el dry-run validaría
# objetos nuevos en vez de intentar modificar el Job de migraciones (inmutable).
chart_output=$(helm template nexo-policy-check ./helm-chart --namespace nexo \
        -f helm-chart/values.yaml -f helm-chart/values-dev.yaml \
    | kubectl apply --dry-run=server -f - 2>&1)
if [ $? -eq 0 ]; then
    chart_status="OK"; PASSED=$((PASSED+1))
else
    chart_status="ERROR"; FAILED=$((FAILED+1))
fi
{
    echo "$chart_output"
    echo "Esperado: ADMITIDO | $chart_status"
    echo ""
    echo "=== Resumen: $PASSED OK, $FAILED con error ==="
} >> "$LOG"
echo "[$chart_status] chart de NEXO"

# Limpieza: el único objeto que se crea de verdad es el good-pod
kubectl delete -f k8s/kyverno/tests/ --ignore-not-found >/dev/null 2>&1

echo ""
echo "Resumen: $PASSED OK, $FAILED con error. Evidencia en $LOG"
[ "$FAILED" -eq 0 ]
