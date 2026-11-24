# NEXO

Sistema de gestión de pedidos e inventario. Es una API REST con **FastAPI** y **PostgreSQL**, empaquetada en Docker, desplegada en Kubernetes con Helm y con un pipeline CI/CD en Jenkins que incluye controles de seguridad (DevSecOps).

---

## Índice

0. [Puesta en marcha rápida (demo)](#puesta-en-marcha-rápida-demo)
1. [Arquitectura](#arquitectura)
2. [Stack tecnológico](#stack-tecnológico)
3. [Estructura del repositorio](#estructura-del-repositorio)
4. [Modelo de datos](#modelo-de-datos)
5. [API](#api)
6. [Ejecución local](#ejecución-local)
7. [Tests](#tests)
8. [Docker](#docker)
9. [Kubernetes con Helm](#kubernetes-con-helm)
10. [Monitorización (Prometheus + Grafana)](#monitorización-prometheus--grafana)
11. [Pipeline CI/CD (Jenkins)](#pipeline-cicd-jenkins)
12. [Seguridad](#seguridad)
13. [Seguridad en el clúster: Kyverno y Falco](#seguridad-en-el-clúster-kyverno-y-falco)
14. [Informes](#informes)

---

## Puesta en marcha rápida (demo)

Todo el entorno se levanta y se borra con scripts (macOS + Docker Desktop + Minikube):

| Script | Qué hace |
|---|---|
| `scripts/start-tools.sh` | Arranca Docker Desktop, Minikube (con `metrics-server`) y Jenkins (`brew services`) |
| `scripts/setup-all.sh` | Todo desde cero: herramientas → operadores (Prometheus Operator/Grafana, Kyverno, Falco) → NEXO con Helm → port-forwards → 60 s de tráfico |
| `scripts/deploy-local.sh` | Construye la imagen dentro de Minikube, crea el Secret de la BD y hace `helm upgrade --install` |
| `scripts/monitoring-up.sh` / `monitoring-down.sh` | Instala o borra kube-prometheus-stack y el dashboard |
| `scripts/generate-traffic.sh [URL] [segundos]` | Genera tráfico realista para poblar los dashboards |
| `scripts/port-forward.sh start\|stop\|status` | API :8000, Grafana :3000, Prometheus :9090 |
| `scripts/teardown-all.sh [--stop-cluster\|--delete-cluster]` | Borra todos los recursos (y opcionalmente para o elimina Minikube) |

```bash
./scripts/setup-all.sh          # ~5-8 min la primera vez
./scripts/teardown-all.sh       # limpiar
```

Al terminar, `setup-all.sh` muestra las URLs y la contraseña de Grafana:

| Servicio | URL |
|---|---|
| API (Swagger) | http://localhost:8000/docs |
| Métricas | http://localhost:8000/metrics |
| Grafana | http://localhost:3000 (dashboard "NEXO - Visión general") |
| Prometheus | http://localhost:9090/targets |
| Jenkins | http://localhost:8080 |

---

## Arquitectura

```
                 ┌──────────────────────── Jenkins ────────────────────────┐
  git push ───►  │ Tests → Semgrep → Snyk → Docker build → Trivy → GHCR →  │
                 │                                         Helm deploy     │
                 └────────────────────────────┬────────────────────────────┘
                                              ▼
              ┌──────────────── Kubernetes (namespace nexo) ───────────────┐
              │                                                            │
  cliente ──► │ Ingress (opcional) ─► Service nexo-api ─► Deployment API   │
              │                                           (FastAPI)        │
              │                                              │             │
              │ Job de migraciones (Alembic) ──────────────► │             │
              │                                              ▼             │
              │                         Service ─► StatefulSet PostgreSQL  │
              │                                     (PVC persistente)      │
              └──────────────────────────────┬─────────────────────────────┘
                                             │ /metrics (ServiceMonitor)
              ┌──────────── Kubernetes (namespace monitoring) ─────────────┐
              │ Prometheus ◄── kube-state-metrics, cAdvisor (CPU/memoria)  │
              │     │                                                      │
              │     ▼                                                      │
              │ Grafana (dashboard "NEXO - Visión general")                │
              └────────────────────────────────────────────────────────────┘
```

## Stack tecnológico

| Capa | Tecnología |
|---|---|
| API | Python 3.12, FastAPI, Uvicorn, Pydantic |
| Persistencia | PostgreSQL 16, SQLAlchemy 2, Alembic (migraciones) |
| Contenedores | Docker multi-stage (`python:3.12-slim-trixie`), Docker Compose |
| Orquestación | Kubernetes (Minikube), Helm 4 |
| CI/CD | Jenkins (declarative pipeline), GitHub Container Registry (GHCR) |
| Observabilidad | `prometheus-client`, Prometheus + Grafana (kube-prometheus-stack) |
| Seguridad | Semgrep (SAST), Snyk (SCA), Trivy (escaneo de imagen), Dive (análisis de capas) |
| Tests | pytest, httpx, SQLite en memoria |

## Estructura del repositorio

```
nexo/
├── app/
│   ├── main.py            # App FastAPI, endpoints de salud y registro de routers
│   ├── config.py          # Configuración vía variables de entorno (pydantic-settings)
│   ├── metrics.py         # Métricas Prometheus (HTTP y negocio) y endpoint /metrics
│   ├── database.py        # Engine, sesiones y Base declarativa de SQLAlchemy
│   ├── models/            # Modelos ORM: Product, Inventory, Order, OrderItem
│   ├── schemas/           # Esquemas Pydantic de entrada/salida
│   └── routers/           # Endpoints: products, orders, inventory
├── migrations/            # Migraciones Alembic (esquema inicial e6a64989b8f6)
├── tests/                 # Tests de pytest (health, products, orders, metrics)
├── docker/Dockerfile      # Imagen multi-stage, usuario no root, HEALTHCHECK
├── compose.yaml           # PostgreSQL + API para desarrollo local
├── helm-chart/            # Chart de Helm (API, PostgreSQL, migraciones, ingress, ServiceMonitor)
├── monitoring/            # Valores de kube-prometheus-stack (Prometheus + Grafana)
├── grafana/dashboard.json # Dashboard de Grafana exportado
├── Jenkinsfile            # Pipeline CI/CD
├── security/semgrep/      # Reglas Semgrep personalizadas
├── k8s/kyverno/           # Políticas de Kyverno (policies/) y manifiestos de prueba (tests/)
├── k8s/falco/             # Pod que dispara la alerta de Falco
├── scripts/               # Utilidades (arranque local, test de concurrencia, análisis de informes)
└── reports/               # Evidencias generadas (tests, escaneos, despliegue)
```

## Modelo de datos

```
products 1 ──── 1 inventory
    │
    └── 1 ──── N order_items N ──── 1 orders
```

| Tabla | Campos principales | Restricciones |
|---|---|---|
| `products` | `name`, `sku` (único), `description`, `price`, `active` | `price >= 0` |
| `inventory` | `product_id` (único), `quantity`, `minimum_stock` (5 por defecto) | `quantity >= 0`, `minimum_stock >= 0` |
| `orders` | `status`, `total_amount`, `created_at` | `total_amount >= 0` |
| `order_items` | `order_id`, `product_id`, `quantity`, `unit_price` | `quantity > 0`, `unit_price >= 0` |

Las restricciones se aplican tanto en Pydantic (validación de entrada) como en la base de datos (`CHECK`), así que no se pueden guardar datos inválidos aunque se salte la API.

## API

La documentación interactiva (Swagger) está en `http://localhost:8000/docs`.

### Salud

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/` | Mensaje de bienvenida |
| GET | `/health` | *Liveness*: el proceso está vivo |
| GET | `/health/ready` | *Readiness*: comprueba la conexión a PostgreSQL (devuelve 503 si falla) |
| GET | `/metrics` | Métricas en formato Prometheus (ver [Monitorización](#monitorización-prometheus--grafana)) |

### Productos

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/products` | Crea un producto y su inventario inicial (409 si el SKU ya existe) |
| GET | `/products?skip=0&limit=100` | Lista productos paginados (`limit` entre 1 y 100) |
| GET | `/products/{id}` | Detalle de un producto con su inventario |
| PUT | `/products/{id}` | Actualización parcial (`name`, `description`, `price`, `active`) |
| DELETE | `/products/{id}` | Baja lógica: marca `active = false` |

### Pedidos

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/orders` | Crea un pedido y descuenta el stock de forma atómica |
| GET | `/orders` | Lista pedidos (más recientes primero) |
| GET | `/orders/{id}` | Detalle de un pedido con sus líneas |

Reglas al crear un pedido:

- No se permiten productos repetidos en el mismo pedido (422).
- Producto inexistente → 404; producto inactivo o stock insuficiente → 409.
- El precio unitario se copia del producto en el momento de la compra.

### Inventario

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/inventory/{product_id}` | Stock actual, mínimo y bandera `low_stock` |
| POST | `/inventory/{product_id}/adjust` | Ajuste positivo o negativo (`{"adjustment": -3}`); no puede quedar negativo (409) ni ser 0 |

### Control de concurrencia

Pedidos y ajustes de inventario bloquean las filas de inventario con `SELECT ... FOR UPDATE`. En los pedidos, los productos se bloquean en orden de `product_id` para evitar *deadlocks*. Así, dos pedidos simultáneos no pueden vender el mismo stock dos veces. El script `scripts/test_concurrency.py` lo comprueba lanzando dos pedidos a la vez sobre el mismo producto: uno devuelve 201 y el otro 409.

### Ejemplo

```bash
# Crear producto con 10 unidades
curl -X POST localhost:8000/products -H 'Content-Type: application/json' \
  -d '{"name":"Teclado","sku":"KB-001","price":"49.90","quantity":10}'

# Hacer un pedido de 2 unidades
curl -X POST localhost:8000/orders -H 'Content-Type: application/json' \
  -d '{"items":[{"product_id":1,"quantity":2}]}'

# Consultar inventario
curl localhost:8000/inventory/1
```

## Ejecución local

### Requisitos

- Python 3.12
- Docker y Docker Compose

### Configuración

```bash
cp .env.example .env
```

| Variable | Descripción | Ejemplo |
|---|---|---|
| `APP_NAME` | Nombre de la aplicación | `NEXO` |
| `APP_ENV` | Entorno | `development` |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | Credenciales de PostgreSQL en Docker Compose (obligatorias) | `nexo` / `CHANGE_ME` / `nexo` |
| `DATABASE_URL` | Cadena de conexión SQLAlchemy | `postgresql+psycopg://nexo:CHANGE_ME@localhost:5435/nexo` |

### Opción A: script de arranque

```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt

./scripts/start-local.sh
```

El script levanta PostgreSQL, espera a que esté listo, aplica las migraciones con Alembic y arranca la API en Docker.

### Opción B: paso a paso

```bash
docker compose up -d postgres      # PostgreSQL en localhost:5435
alembic upgrade head               # aplicar migraciones
uvicorn app.main:app --reload      # API en localhost:8000
```

## Tests

```bash
pytest -v
```

Los tests usan SQLite en memoria (sustituyen la dependencia `get_db`), así que no necesitan PostgreSQL. Cubren los endpoints de salud, el CRUD de productos y la lógica de pedidos (stock, duplicados, productos inactivos) y las métricas Prometheus. Hay 24 tests.

Test de concurrencia contra una instancia real (requiere la API levantada):

```bash
python scripts/test_concurrency.py
```

## Docker

`docker/Dockerfile` usa dos etapas:

1. **builder**: crea un *virtualenv* en `/opt/venv` con las dependencias de producción.
2. **runtime**: copia solo el *virtualenv*, el código, las migraciones y `alembic.ini`.

Medidas de hardening:

- Imagen base `slim-trixie` con versión fija; se cambió de bookworm a trixie para eliminar CVEs críticas.
- Se ejecuta como usuario sin privilegios `nexo`.
- `HEALTHCHECK` contra `/health`.
- `.dockerignore` excluye tests, informes y ficheros locales.

```bash
docker build -f docker/Dockerfile -t nexo-api:local .
docker compose up -d
```

## Kubernetes con Helm

El chart (`helm-chart/`) despliega:

| Recurso | Descripción |
|---|---|
| `api-deployment.yaml` | Deployment de la API con probes de *liveness* (`/health`) y *readiness* (`/health/ready`), límites de recursos y `securityContext` no root |
| `api-service.yaml` | Service ClusterIP en el puerto 8000 |
| `postgres-statefulset.yaml` | PostgreSQL con volumen persistente (PVC) |
| `postgres-service.yaml` | Service interno de la base de datos |
| `migration-job.yaml` | Job que espera a PostgreSQL y ejecuta `alembic upgrade` en cada release |
| `configmap.yaml` | Configuración de la app (las credenciales van en el Secret `nexo-secret`, creado aparte) |
| `servicemonitor.yaml` | ServiceMonitor para que Prometheus recoja `/metrics` (solo si el clúster tiene la CRD de Prometheus Operator) |
| `ingress.yaml` | Ingress nginx (opcional) |

Ficheros de valores por entorno:

| Fichero | Réplicas | Ingress | Almacenamiento BD |
|---|---|---|---|
| `values.yaml` (base) | 2 | no | 1Gi |
| `values-dev.yaml` | 1 | no | 1Gi |
| `values-prod.yaml` | 3 | sí (`nexo.example.com`) | 10Gi |

La imagen se descarga de GHCR, así que el namespace necesita un secret `ghcr-secret`:

```bash
kubectl create namespace nexo
./scripts/create-db-secret.sh      # Secret nexo-secret con contraseña aleatoria
kubectl create secret docker-registry ghcr-secret -n nexo \
  --docker-server=ghcr.io --docker-username=<usuario> --docker-password=<token>

helm upgrade --install nexo ./helm-chart -n nexo \
  -f helm-chart/values.yaml -f helm-chart/values-dev.yaml

kubectl port-forward svc/nexo-api 8000:8000 -n nexo
```

## Monitorización (Prometheus + Grafana)

### Instrumentación de la API

`app/metrics.py` usa `prometheus-client`. Un *middleware* mide todas las peticiones y la API publica las métricas en `GET /metrics`:

| Métrica | Tipo | Etiquetas | Qué mide |
|---|---|---|---|
| `nexo_http_requests_total` | Counter | `method`, `handler`, `status` | Peticiones procesadas |
| `nexo_http_request_duration_seconds` | Histogram | `method`, `handler` | Latencia de respuesta |
| `nexo_http_requests_in_progress` | Gauge | — | Peticiones en curso |
| `nexo_orders_created_total` | Counter | — | **Negocio:** pedidos confirmados |
| `nexo_order_revenue_total` | Counter | — | **Negocio:** importe facturado |
| `nexo_order_items_sold_total` | Counter | — | **Negocio:** unidades vendidas |
| `nexo_orders_rejected_total` | Counter | `reason` | **Negocio:** pedidos rechazados (`insufficient_stock`, `product_not_found`, `product_inactive`, `duplicate_products`) |

`handler` es la plantilla de la ruta (`/orders/{order_id}`), no la URL concreta, para que el número de series no crezca con cada id. `/metrics` no se cuenta a sí mismo.

```bash
curl -s localhost:8000/metrics | grep ^nexo_
```

### Despliegue de Prometheus y Grafana

Se usa el chart oficial `prometheus-community/kube-prometheus-stack` (versión fija 93.9.0) con los valores de `monitoring/kube-prometheus-stack-values.yaml`:

- Prometheus descubre los `ServiceMonitor` de cualquier namespace.
- Grafana viene con Prometheus ya configurado como fuente de datos. Su usuario admin está en el Secret `grafana-admin` (contraseña aleatoria).
- Un *sidecar* de Grafana carga automáticamente los dashboards de los ConfigMaps con la etiqueta `grafana_dashboard=1`.
- Se desactivan Alertmanager y los componentes del *control plane* que Minikube no expone.

El chart de NEXO crea el `ServiceMonitor` `nexo-api`, que le dice a Prometheus que lea `/metrics` del Service de la API cada 15 s. Las métricas de CPU y memoria por pod vienen de cAdvisor (kubelet) y kube-state-metrics, que instala el propio stack.

```bash
./scripts/monitoring-up.sh          # instala el stack y carga el dashboard
# (re)desplegar NEXO después, para que Helm cree el ServiceMonitor
helm upgrade --install nexo ./helm-chart -n nexo -f helm-chart/values-dev.yaml

# Grafana: http://localhost:3000 (usuario admin)
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
kubectl get secret grafana-admin -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d; echo

# Prometheus: http://localhost:9090/targets
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090

./scripts/monitoring-down.sh        # desinstalar (--purge-crds borra también las CRDs)
```

### Dashboard

`grafana/dashboard.json` es el dashboard exportado ("NEXO - Visión general", uid `nexo-overview`). Tiene una variable `namespace` (por defecto `nexo`) y estos paneles:

| Sección | Panel | Consulta (resumida) |
|---|---|---|
| Resumen | Peticiones por segundo (RPS) | `sum(rate(nexo_http_requests_total[…]))` |
| Resumen | Latencia media | `rate(…_duration_seconds_sum) / rate(…_duration_seconds_count)` |
| Resumen | Tasa de errores 5xx | 5xx / total |
| Resumen | Pedidos confirmados, Facturación | `increase(nexo_orders_created_total[$__range])`, `increase(nexo_order_revenue_total[$__range])` |
| Tráfico y latencia | RPS por endpoint, por código de estado | `sum by (method, handler)`, `sum by (status)` |
| Tráfico y latencia | Latencia media y p95, latencia por endpoint | `histogram_quantile(0.95, …_bucket)` |
| Recursos por pod | Uso de CPU por pod (y límite) | `rate(container_cpu_usage_seconds_total{container="api"})` |
| Recursos por pod | Uso de memoria por pod (y límite) | `container_memory_working_set_bytes{container="api"}` |
| Negocio | Pedidos por minuto (confirmados / rechazados por motivo) | `rate(nexo_orders_created_total)`, `rate(nexo_orders_rejected_total) by (reason)` |
| Negocio | Facturación y unidades vendidas por minuto | `rate(nexo_order_revenue_total)`, `rate(nexo_order_items_sold_total)` |

Para que los paneles tengan datos, se genera tráfico contra la API:

```bash
kubectl port-forward svc/nexo-api 8000:8000 -n nexo &
./scripts/generate-traffic.sh http://localhost:8000 300   # 5 minutos
```

El script crea productos, hace pedidos (algunos fallan a propósito por stock insuficiente o producto inexistente), repone stock y consulta productos, inventario y pedidos.

## Pipeline CI/CD (Jenkins)

`Jenkinsfile` define estas etapas, en orden:

| # | Etapa | Qué hace | Falla si… |
|---|---|---|---|
| 1 | Checkout | Clona el repositorio | — |
| 2 | Environment Setup | Crea un venv e instala `requirements-dev.txt` | falla la instalación |
| 3 | Tests | `pytest` con informe JUnit | falla algún test |
| 4 | Semgrep Security Scan | SAST con reglas propias (`security/semgrep/rules.yml`) | hay hallazgos |
| 5 | Snyk Dependency Scan | SCA de dependencias de producción y desarrollo; `scripts/check_snyk.py` revisa los resultados | hay vulnerabilidades **críticas** |
| 6 | Docker Build | Construye `ghcr.io/amandaseara/nexo-api:build-<N>` | falla el build |
| 7 | Trivy Image Scan | Escanea la imagen (informe HIGH/CRITICAL) | hay CVEs **críticas** |
| 8 | Publish to GHCR | Publica la imagen en GitHub Container Registry | falla el push |
| 9 | Deploy to Kubernetes | `helm upgrade --install` con la nueva etiqueta, espera el rollout y verifica que la imagen desplegada es la esperada | el rollout falla o la imagen no coincide |

Al final siempre se publican los resultados JUnit y se archivan los informes como artefactos.

Credenciales necesarias en Jenkins:

| ID | Tipo | Uso |
|---|---|---|
| `SNYK_TOKEN` | Secret text | Autenticación en Snyk |
| `GHCR_CREDENTIALS` | Usuario/contraseña | Push a GHCR |

El agente necesita Python 3, Docker, Semgrep, Snyk CLI, Trivy, Helm y `kubectl` con acceso al clúster.

## Seguridad

| Herramienta | Tipo | Objetivo |
|---|---|---|
| Semgrep | SAST | Detecta `subprocess(..., shell=True)` (CWE-78) y `eval()` (CWE-95) |
| Snyk | SCA | Vulnerabilidades en dependencias Python |
| Trivy | Escaneo de imagen | CVEs del sistema operativo y librerías de la imagen |
| Dive | Análisis de capas | Eficiencia y tamaño de la imagen |
| Kyverno | Políticas de admisión | Rechaza Pods inseguros antes de que se creen |
| Falco | Seguridad en ejecución | Detecta comportamiento sospechoso en contenedores que ya están corriendo |

Medidas en el despliegue: contenedores no root, `seccompProfile: RuntimeDefault`, sin token de *service account* montado en el Job de migraciones, límites de CPU/memoria, credenciales en `Secret` y PostgreSQL publicado solo en `127.0.0.1` en local.

## Seguridad en el clúster: Kyverno y Falco

Las dos herramientas cubren momentos distintos de la vida de un Pod:

```
kubectl apply / helm install
        │
        ▼
  API server ──► Kyverno (admission webhook) ── no cumple ──► rechazado, el Pod nunca se crea
        │ cumple
        ▼
  Pod corriendo ──► syscalls (open, execve...) ──► Falco (driver eBPF) ──► alerta en sus logs
```

- **Kyverno es preventivo:** revisa cómo está configurado un objeto *antes* de guardarlo en el clúster.
- **Falco es detectivo:** mira qué hace el contenedor *mientras corre*. Avisa, no bloquea.

### Instalación

```bash
./scripts/install-security.sh
```

Instala Kyverno (chart `kyverno/kyverno` 3.10.0, Kyverno v1.20) y Falco (chart `falcosecurity/falco` 9.2.2, Falco 0.45, driver `modern_ebpf`) con Helm, y aplica las políticas de `k8s/kyverno/policies/`. Es idempotente.

### Políticas de Kyverno

Kyverno v1.20 ya no acepta el formato `ClusterPolicy`. Las políticas usan el tipo nuevo, `ValidatingPolicy`: cada regla es una expresión CEL que tiene que dar `true`, y `validationActions: [Deny]` rechaza lo que no cumple. Aplican al namespace `nexo`.

| Política | Qué exige | Por qué |
|---|---|---|
| `disallow-latest-tag` | Imagen con tag explícito y distinto de `latest` | `latest` cambia con el tiempo: el mismo despliegue podría correr imágenes distintas |
| `require-requests-limits` | Requests y limits de CPU y memoria en todos los contenedores (también los initContainers) | Sin límites, un Pod puede consumir todo el nodo |
| `require-run-as-non-root` | `securityContext.runAsNonRoot: true` en el Pod | Si explotan la app, root facilita escalar y escaparse al nodo |
| `require-probes` (extra) | `readinessProbe` y `livenessProbe` en Deployments y StatefulSets | Sin readiness, el rolling update manda tráfico a Pods que no están listos; sin liveness, un proceso colgado nunca se reinicia. No aplica a Jobs: corren y terminan |

Las tres primeras validan Pods y, con `autogen`, también Deployments, StatefulSets y Jobs, así el error aparece al hacer el `apply` y no después, cuando el ReplicaSet intenta crear los Pods.

Ejemplo, la política de `latest`:

```yaml
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationActions: [Deny]
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [pods]
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: nexo
  variables:
    - name: images
      expression: "object.spec.containers.map(c, c.image)"
  validations:
    - expression: "variables.images.all(img, !img.endsWith(':latest'))"
      message: "No se permite el tag 'latest'. Usá una versión fija."
```

### Validación de las políticas

```bash
./scripts/validate-kyverno.sh
```

Aplica cada manifiesto de `k8s/kyverno/tests/`. Cada uno rompe una sola política, salvo `00-good-pod.yaml`, que cumple todas. Además renderiza el chart de NEXO y lo pasa por Kyverno con `kubectl apply --dry-run=server` para comprobar que la aplicación cumple las 4 políticas. La evidencia queda en `reports/kyverno-validation.log`.

Resultado (fragmento):

```
--- 01-bad-latest-tag.yaml ---
Error from server: ... admission webhook "vpol.validate.kyverno.svc-fail-..." denied the request:
Policy disallow-latest-tag failed: No se permite el tag 'latest'. Usá una versión fija.
Esperado: RECHAZADO | Resultado: RECHAZADO | OK

--- 04-bad-no-probes.yaml ---
Error from server: ... denied the request:
Policy require-probes failed: Los contenedores deben definir readinessProbe y livenessProbe.
Esperado: RECHAZADO | Resultado: RECHAZADO | OK

--- Chart de NEXO (helm template + kubectl apply --dry-run=server) ---
deployment.apps/nexo-api created (server dry run)
statefulset.apps/nexo-postgres created (server dry run)
job.batch/nexo-migrations-1 created (server dry run)
Esperado: ADMITIDO | OK

=== Resumen: 7 OK, 0 con error ===
```

### Evento de Falco

```bash
./scripts/trigger-falco.sh
```

Lanza `k8s/falco/falco-test-pod.yaml`: un Pod que ejecuta `find /etc /home -name id_rsa`, o sea que busca claves privadas SSH. Es lo que hace un atacante después de entrar a un contenedor: buscar credenciales para saltar a otros sistemas. Falco ve la syscall `execve` del proceso `find` y dispara la regla por defecto **Search Private Keys or Passwords** (prioridad Warning).

El Pod cumple a propósito las 4 políticas de Kyverno (tag fijo, no root, límites): Kyverno lo deja entrar porque está bien configurado, y aun así Falco detecta lo que hace una vez que corre. Tampoco abre un shell, que la consigna no permite como evento.

Alerta registrada (en `reports/falco-event.log`, recortada):

```
Warning Grep private keys or passwords activities found | evt_type=execve user_uid=1000
process=find command=find /etc /home -name id_rsa container_image_repository=busybox
container_image_tag=1.36 k8s_pod_name=falco-test k8s_ns_name=nexo
```

## Informes

En `reports/` están las evidencias de cada fase:

| Carpeta | Contenido |
|---|---|
| `reports/database/` | Resultados de pytest, estado de Alembic y test de concurrencia |
| `reports/image-analysis.md` | Informe de la imagen: tamaño (240,6 MB), 10 capas, eficiencia y optimizaciones posibles |
| `reports/image-analysis/` | Trivy antes y después del hardening, Dive, `docker history` e `inspect` (también de la 0.4.0) |
| `reports/jenkins/` | Pruebas del *gate* de Trivy en el pipeline |
| `reports/kubernetes/` | Estado de Minikube, pods, servicios, Helm y checks de salud |
| `reports/semgrep-report.txt` | Semgrep: reglas aplicadas, 0 hallazgos en el proyecto y validación de las reglas con un ejemplo vulnerable |
| `reports/monitoring/` | Pods, ServiceMonitor, targets de Prometheus y consultas de los paneles de Grafana |
| `grafana/dashboard.json` | Dashboard de Grafana exportado |
| `reports/kyverno-validation.log` | Pods rechazados y admitidos por cada política de Kyverno |
| `reports/falco-event.log` | Alerta de Falco y descripción del evento |

`scripts/compare_trivy.py` resume y compara los informes de Trivy de la imagen inicial y la final.
