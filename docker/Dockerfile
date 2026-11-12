
# Builder
FROM python:3.12.16-slim-trixie AS builder

WORKDIR /build

COPY requirements.txt .

RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir \
       -r requirements.txt


# Runtime
FROM python:3.12.16-slim-trixie AS runtime

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN groupadd --system nexo \
    && useradd --system --gid nexo \
       --home-dir /app nexo

COPY --from=builder /opt/venv /opt/venv

COPY --chown=nexo:nexo app/ ./app/
COPY --chown=nexo:nexo migrations/ ./migrations/
COPY --chown=nexo:nexo alembic.ini ./alembic.ini

USER nexo

EXPOSE 8000

HEALTHCHECK --interval=30s \
    --timeout=5s \
    --start-period=15s \
    --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3)"

CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", "--port", "8000"]
