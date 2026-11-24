# Builder
FROM python:3.12.16-slim-trixie AS builder

WORKDIR /build

COPY requirements.txt .

RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir \
       -r requirements.txt

# Runtime
FROM python:3.12.16-slim-trixie AS runtime

ARG APP_VERSION=0.4.0

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION}

LABEL org.opencontainers.image.title="NEXO"
LABEL org.opencontainers.image.version="${APP_VERSION}"
LABEL org.opencontainers.image.source="https://github.com/amandaseara/nexo"

WORKDIR /app

RUN groupadd --gid 10001 nexo \
    && useradd --uid 10001 \
       --gid 10001 \
       --home-dir /app \
       --no-create-home \
       --shell /usr/sbin/nologin \
       nexo

COPY --from=builder /opt/venv /opt/venv

COPY --chown=10001:10001 app/ ./app/
COPY --chown=10001:10001 migrations/ ./migrations/
COPY --chown=10001:10001 alembic.ini ./alembic.ini

USER 10001:10001

EXPOSE 8000

HEALTHCHECK --interval=30s \
    --timeout=5s \
    --start-period=15s \
    --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3)"

CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", "--port", "8000"]
