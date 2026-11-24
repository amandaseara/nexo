#!/usr/bin/env bash
# Despliega NEXO en Minikube con una imagen construida desde el árbol de
# trabajo local (incluye cambios sin commitear, p. ej. el endpoint /metrics).
#
#   1. Construye la imagen directamente en el Docker de Minikube
#      (no se sube a ningún registro; tag distinto de "latest").
#   2. Crea el namespace y el Secret de la base de datos si no existen
#      (scripts/create-db-secret.sh).
#   3. helm upgrade --install con values-dev.yaml y la imagen local.
#
# Uso: scripts/deploy-local.sh
# Variables:
#   NAMESPACE   (nexo)       RELEASE (nexo)
#   IMAGE_REPO  (nexo-api)   IMAGE_TAG (local-<sha>[-dirty<hash>])
#   MINIKUBE_SHIM  ruta a una dylib para DYLD_INSERT_LIBRARIES (solo macOS;
#                  workaround del crash de minikube en Apple M6). Por defecto
#                  se usa ~/.minikube-m6-shim/libminikube-m6-shim.dylib si existe.
#
# Recomendado: ejecutar antes scripts/monitoring-up.sh para que Helm cree el
# ServiceMonitor (solo se renderiza si existe la CRD de Prometheus Operator).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-nexo}"
RELEASE="${RELEASE:-nexo}"
IMAGE_REPO="${IMAGE_REPO:-nexo-api}"
MINIKUBE_SHIM="${MINIKUBE_SHIM:-${HOME}/.minikube-m6-shim/libminikube-m6-shim.dylib}"

cd "$ROOT_DIR"

# minikube con el shim (si existe) para evitar el SIGSEGV de gopsutil en M6.
mk() {
    if [[ "$(uname -s)" == "Darwin" && -f "$MINIKUBE_SHIM" ]]; then
        DYLD_INSERT_LIBRARIES="$MINIKUBE_SHIM" minikube "$@"
    else
        minikube "$@"
    fi
}

for cmd in minikube kubectl helm docker git; do
    command -v "$cmd" >/dev/null 2>&1 \
        || { echo "Falta el comando '$cmd'." >&2; exit 1; }
done

# Tag reproducible: commit actual + hash del contenido que entra en la imagen
# si hay cambios sin commitear. Así cada cambio de código fuerza un rollout.
if [[ -z "${IMAGE_TAG:-}" ]]; then
    SHORT_SHA="$(git rev-parse --short HEAD)"
    BUILD_INPUTS=(app migrations alembic.ini requirements.txt docker/Dockerfile)
    if [[ -n "$(git status --porcelain -- "${BUILD_INPUTS[@]}")" ]]; then
        CONTENT_HASH="$(git ls-files -co --exclude-standard -- "${BUILD_INPUTS[@]}" \
            | LC_ALL=C sort | tr '\n' '\0' | xargs -0 shasum -a 256 \
            | shasum -a 256 | cut -c1-8)"
        IMAGE_TAG="local-${SHORT_SHA}-dirty${CONTENT_HASH}"
    else
        IMAGE_TAG="local-${SHORT_SHA}"
    fi
fi
if [[ "$IMAGE_TAG" == "latest" ]]; then
    echo "No se permite el tag 'latest'." >&2
    exit 1
fi
APP_VERSION="$(awk -F'"' '/^appVersion:/ {print $2}' helm-chart/Chart.yaml)"

echo "[1/5] Comprobando Minikube..."
if ! mk status >/dev/null 2>&1; then
    echo "      Minikube no está arrancado. Ejecuta: minikube start" >&2
    exit 1
fi
kubectl config use-context minikube >/dev/null

echo "[2/5] Construyendo ${IMAGE_REPO}:${IMAGE_TAG} dentro de Minikube..."
# Docker CLI local contra el daemon de Minikube: respeta .dockerignore y la
# imagen queda disponible para el kubelet sin registro.
eval "$(mk docker-env --shell bash)"
docker build \
    -f docker/Dockerfile \
    --build-arg APP_VERSION="$APP_VERSION" \
    -t "${IMAGE_REPO}:${IMAGE_TAG}" \
    .
eval "$(mk docker-env --shell bash --unset)"

echo "[3/5] Namespace y Secret de la base de datos..."
NAMESPACE="$NAMESPACE" RELEASE="$RELEASE" "$ROOT_DIR/scripts/create-db-secret.sh"

echo "[4/5] Comprobando la CRD de ServiceMonitor..."
if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    echo "      CRD presente: se creará el ServiceMonitor."
else
    echo "      AVISO: no existe la CRD; no se creará el ServiceMonitor."
    echo "      Ejecuta scripts/monitoring-up.sh y vuelve a lanzar este script."
fi

echo "[5/5] helm upgrade --install ${RELEASE} (puede tardar unos minutos)..."
helm upgrade --install "$RELEASE" ./helm-chart \
    --namespace "$NAMESPACE" \
    -f helm-chart/values-dev.yaml \
    --set-string image.repository="$IMAGE_REPO" \
    --set-string image.tag="$IMAGE_TAG" \
    --set-string image.pullPolicy=Never \
    --wait \
    --wait-for-jobs \
    --timeout 10m

kubectl get pods -n "$NAMESPACE" -o wide

cat <<INFO

NEXO desplegado con la imagen local ${IMAGE_REPO}:${IMAGE_TAG}.

  API:      kubectl port-forward -n ${NAMESPACE} svc/${RELEASE}-api 8000:8000
            http://localhost:8000/docs   http://localhost:8000/metrics
  Tráfico:  scripts/generate-traffic.sh http://localhost:8000 180
INFO
