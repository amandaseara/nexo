# NEXO

Sistema de gestión de pedidos e inventario. Es una API REST con **FastAPI** y **PostgreSQL**, empaquetada en Docker, desplegada en Kubernetes con Helm y con un pipeline CI/CD en Jenkins que incluye controles de seguridad (DevSecOps).

---

## Índice

1. [Arquitectura](#arquitectura)
2. [Stack tecnológico](#stack-tecnológico)
3. [Estructura del repositorio](#estructura-del-repositorio)
4. [Modelo de datos](#modelo-de-datos)
5. [API](#api)
6. [Ejecución local](#ejecución-local)
7. [Tests](#tests)
8. [Docker](#docker)
9. [Kubernetes con Helm](#kubernetes-con-helm)
10. [Pipeline CI/CD (Jenkins)](#pipeline-cicd-jenkins)
11. [Seguridad](#seguridad)
12. [Informes](#informes)

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
              └────────────────────────────────────────────────────────────┘
```

## Stack tecnológico

| Capa | Tecnología |
|---|---|
| API | Python 3.12, FastAPI, Uvicorn, Pydantic |
| Persistencia | PostgreSQL 16, SQLAlchemy 2, Alembic (migraciones) |
| Contenedores | Docker multi-stage (`python:3.12-slim-trixie`), Docker Compose |
| Orquestación | Kubernetes (Minikube), Helm 3 |
| CI/CD | Jenkins (declarative pipeline), GitHub Container Registry (GHCR) |
| Seguridad | Semgrep (SAST), Snyk (SCA), Trivy (escaneo de imagen), Dive (análisis de capas) |
| Tests | pytest, httpx, SQLite en memoria |

## Estructura del repositorio

```
nexo/
├── app/
│   ├── main.py            # App FastAPI, endpoints de salud y registro de routers
│   ├── config.py          # Configuración vía variables de entorno (pydantic-settings)
│   ├── database.py        # Engine, sesiones y Base declarativa de SQLAlchemy
│   ├── models/            # Modelos ORM: Product, Inventory, Order, OrderItem
│   ├── schemas/           # Esquemas Pydantic de entrada/salida
│   └── routers/           # Endpoints: products, orders, inventory
├── migrations/            # Migraciones Alembic (esquema inicial e6a64989b8f6)
├── tests/                 # Tests de pytest (health, products, orders)
├── docker/Dockerfile      # Imagen multi-stage, usuario no root, HEALTHCHECK
├── compose.yaml           # PostgreSQL + API para desarrollo local
├── helm-chart/            # Chart de Helm (API, PostgreSQL, migraciones, ingress)
├── Jenkinsfile            # Pipeline CI/CD
├── security/semgrep/      # Reglas Semgrep personalizadas
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
| `DATABASE_URL` | Cadena de conexión SQLAlchemy | `postgresql+psycopg://nexo:nexo_password@localhost:5435/nexo` |

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

Los tests usan SQLite en memoria (sustituyen la dependencia `get_db`), así que no necesitan PostgreSQL. Cubren los endpoints de salud, el CRUD de productos y la lógica de pedidos (stock, duplicados, productos inactivos). Hay 19 tests.

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
| `configmap.yaml` / `secret.yaml` | Configuración de la app y credenciales de la base de datos |
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
kubectl create secret docker-registry ghcr-secret -n nexo \
  --docker-server=ghcr.io --docker-username=<usuario> --docker-password=<token>

helm upgrade --install nexo ./helm-chart -n nexo \
  -f helm-chart/values.yaml -f helm-chart/values-dev.yaml

kubectl port-forward svc/nexo-api 8000:8000 -n nexo
```

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

Medidas en el despliegue: contenedores no root, `seccompProfile: RuntimeDefault`, sin token de *service account* montado en el Job de migraciones, límites de CPU/memoria, credenciales en `Secret` y PostgreSQL publicado solo en `127.0.0.1` en local.

## Informes

En `reports/` están las evidencias de cada fase:

| Carpeta | Contenido |
|---|---|
| `reports/database/` | Resultados de pytest, estado de Alembic y test de concurrencia |
| `reports/image-analysis/` | Trivy antes y después del hardening, Dive, `docker history` e `inspect` |
| `reports/jenkins/` | Pruebas del *gate* de Trivy en el pipeline |
| `reports/kubernetes/` | Estado de Minikube, pods, servicios, Helm y checks de salud |
| `reports/semgrep-report.*` | Resultado del análisis Semgrep |

`scripts/compare_trivy.py` resume y compara los informes de Trivy de la imagen inicial y la final.
