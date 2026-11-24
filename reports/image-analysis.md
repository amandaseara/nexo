# Análisis de la imagen Docker de NEXO

Imagen analizada: `nexo-api:0.4.0`, construida con `docker/Dockerfile` desde el código actual. La construcción local fue en arm64 (Apple Silicon); Jenkins construye amd64, con tamaños casi iguales.

Herramientas:
- **Dive** v0.13.1 para el tamaño y las capas: `dive nexo-api:0.4.0 --ci --json`. La letra pide SlimToolkit en macOS, pero Dive hace el mismo análisis de capas y se ejecuta igual en contenedor.
- **Trivy** para las vulnerabilidades.
- `docker history` / `docker image inspect` para los datos de la imagen.

Evidencias:
- `reports/image-analysis/dive-0.4.0.json`
- `reports/image-analysis/trivy-0.4.0.txt`
- `reports/image-analysis/docker-history-0.4.0.txt`
- Análisis de versiones anteriores, en la misma carpeta.

## Resumen

| Dato | Valor |
|---|---|
| Tamaño total | **240,6 MB** (240.601.167 bytes) |
| Capas con contenido (`RootFS.Layers`) | **10** |
| Eficiencia (Dive) | **98,4 %** |
| Espacio desperdiciado (Dive) | 5,65 MB |
| Usuario de ejecución | `10001:10001` (no root) |
| Imagen base | `python:3.12.16-slim-trixie` (versión fija, no `latest`) |
| Vulnerabilidades (Trivy) | 53 HIGH, **0 CRITICAL** |

## Capas

| # | Tamaño | Origen |
|---|---|---|
| 0 | 100,6 MB | Debian 13 (trixie) base |
| 1 | 3,8 MB | `apt-get install ca-certificates…` (imagen oficial de Python) |
| 2 | 40,1 MB | Intérprete CPython 3.12.16 (imagen oficial de Python) |
| 3 | 0 | Enlaces simbólicos `python3`, `pip3`… |
| 4 | 0 | `WORKDIR /app` |
| 5 | 4 kB | Creación del usuario `nexo` (UID/GID 10001) |
| 6 | **96,0 MB** | `COPY /opt/venv` (dependencias, desde la etapa *builder*) |
| 7 | 54 kB | Código de la aplicación (`app/`) |
| 8 | 13 kB | Migraciones Alembic |
| 9 | 5 kB | `alembic.ini` |

El 59 % de la imagen es la base de Debian y Python (capas 0 a 2), que no controlamos. El 40 % es el *virtualenv* (capa 6). Nuestro código ocupa menos de 0,1 MB.

Dentro del *virtualenv*, los paquetes más grandes son:

| Paquete | Tamaño |
|---|---|
| `sqlalchemy` | 23 MB |
| `uvloop` | 17 MB |
| `pip` | 13 MB |
| `psycopg_binary` (libpq) | 12 MB |
| `pydantic(_core)` | 10 MB |
| Ficheros `__pycache__` | 27 MB en total |

## Lo que ya está optimizado

- **Multi-stage build:** la etapa *builder* instala las dependencias en `/opt/venv`, y la imagen final solo copia el *virtualenv* y el código. No quedan compiladores, cabeceras ni caché de pip (`--no-cache-dir`).
- **Base `slim`:** frente a `python:3.12` completa (~1 GB) se ahorran unos 800 MB.
- **Cambio de bookworm a trixie:** se pasó de 9 CVE CRITICAL a 0. Comparativa en `trivy-initial.txt` y `trivy-final.txt`.
- **`.dockerignore`:** excluye tests, informes, `.git`, `.venv` y `.env`.
- **Orden de capas:** el código y las migraciones (lo que más cambia) van al final, así la caché de dependencias se reaprovecha entre builds.
- **Eficiencia del 98,4 %:** los 5,6 MB desperdiciados son ficheros de `debconf`/`dpkg` repetidos en las capas de la imagen base oficial, no en las nuestras.

## Optimizaciones posibles

| Mejora | Ahorro estimado | Coste / riesgo |
|---|---|---|
| Quitar `pip`, `setuptools` y `wheel` del venv final (`pip uninstall -y pip setuptools` en el *builder*) | ~13–15 MB | Ninguno: en producción no se instalan paquetes |
| `uvicorn` sin `[standard]` (sin `uvloop`, `httptools`, `watchfiles` ni `websockets`) | ~25 MB | Algo menos de rendimiento HTTP. Se puede dejar `uvloop` y quitar solo `watchfiles`, que solo sirve para `--reload` |
| No guardar `.pyc` en la imagen (`PYTHONDONTWRITEBYTECODE` en el *builder* o borrar `__pycache__`) | hasta ~27 MB | Arranque algo más lento la primera vez |
| Imagen base *distroless* (`gcr.io/distroless/python3-debian12`) o Chainguard | ~60–80 MB y muchas menos CVE del sistema | No hay `sh`: el `HEALTHCHECK` y el *init container* (`sh -c`) tendrían que reescribirse |
| Alpine (`python:3.12-alpine`) | ~50 MB | `psycopg[binary]` y `uvloop` no tienen *wheels* musl en todas las versiones: habría que compilar |
| Actualizar los paquetes del sistema (`apt-get upgrade`) o reconstruir cuando salga una base nueva | Reduce las 53 HIGH | Imagen menos reproducible; mejor reconstruir periódicamente en Jenkins |
