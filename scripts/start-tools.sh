#!/usr/bin/env bash
# Arranca los componentes base de la demo en macOS:
# Docker Desktop, Minikube y Jenkins (brew services).
# Uso: scripts/start-tools.sh
set -euo pipefail

echo "[1/3] Docker..."
if ! docker info >/dev/null 2>&1; then
    open -a Docker
    until docker info >/dev/null 2>&1; do sleep 3; done
fi
echo "      Docker listo."

echo "[2/3] Minikube..."
if ! minikube status >/dev/null 2>&1; then
    # En Apple M6 / macOS 27 "minikube start" falla al leer la CPU del host;
    # si existe la librería de compatibilidad local, se usa solo para este comando.
    SHIM="${HOME}/.minikube-m6-shim/libminikube-m6-shim.dylib"
    if [[ -f $SHIM ]]; then
        DYLD_INSERT_LIBRARIES="$SHIM" minikube start --container-runtime=docker \
            --cpus="${MINIKUBE_CPUS:-4}" --memory="${MINIKUBE_MEMORY:-6g}"
    else
        minikube start --container-runtime=docker \
            --cpus="${MINIKUBE_CPUS:-4}" --memory="${MINIKUBE_MEMORY:-6g}"
    fi
fi
minikube addons enable metrics-server >/dev/null 2>&1 || true
kubectl config use-context minikube >/dev/null
echo "      Clúster listo: $(kubectl get nodes --no-headers | awk '{print $1, $2, $5}')"

echo "[3/3] Jenkins..."
brew services start jenkins-lts >/dev/null 2>&1 || true
until curl -s -o /dev/null http://localhost:8080/login; do sleep 2; done
echo "      Jenkins: http://localhost:8080"
