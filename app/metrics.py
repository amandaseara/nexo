"""Métricas Prometheus de NEXO.

Técnicas (tráfico HTTP):
- nexo_http_requests_total{method, handler, status}
- nexo_http_request_duration_seconds{method, handler}  (histograma)
- nexo_http_requests_in_progress

Negocio (pedidos):
- nexo_orders_created_total
- nexo_order_revenue_total
- nexo_order_items_sold_total
- nexo_orders_rejected_total{reason}

`handler` es la plantilla de la ruta (p. ej. /orders/{order_id}), no la URL
real, para que la cardinalidad de las series no crezca con cada id.
"""

import time

from fastapi import FastAPI, Request, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

METRICS_PATH = "/metrics"

HTTP_REQUESTS = Counter(
    "nexo_http_requests_total",
    "Peticiones HTTP procesadas.",
    ["method", "handler", "status"],
)

HTTP_LATENCY = Histogram(
    "nexo_http_request_duration_seconds",
    "Latencia de las peticiones HTTP en segundos.",
    ["method", "handler"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)

HTTP_IN_PROGRESS = Gauge(
    "nexo_http_requests_in_progress",
    "Peticiones HTTP en curso.",
)

ORDERS_CREATED = Counter(
    "nexo_orders_created_total",
    "Pedidos confirmados.",
)

ORDER_REVENUE = Counter(
    "nexo_order_revenue_total",
    "Importe acumulado de los pedidos confirmados.",
)

ORDER_ITEMS_SOLD = Counter(
    "nexo_order_items_sold_total",
    "Unidades vendidas en pedidos confirmados.",
)

ORDERS_REJECTED = Counter(
    "nexo_orders_rejected_total",
    "Pedidos rechazados, por motivo.",
    ["reason"],
)


def _handler_of(request: Request) -> str:
    route = request.scope.get("route")
    return getattr(route, "path", "unmatched")


def setup_metrics(app: FastAPI) -> None:
    """Registra el middleware de instrumentación y el endpoint /metrics."""

    @app.middleware("http")
    async def prometheus_middleware(request: Request, call_next):
        if request.url.path == METRICS_PATH:
            return await call_next(request)

        method = request.method
        status = "500"
        start = time.perf_counter()
        HTTP_IN_PROGRESS.inc()

        try:
            response = await call_next(request)
            status = str(response.status_code)
            return response
        finally:
            handler = _handler_of(request)
            HTTP_LATENCY.labels(method, handler).observe(
                time.perf_counter() - start
            )
            HTTP_REQUESTS.labels(method, handler, status).inc()
            HTTP_IN_PROGRESS.dec()

    @app.get(METRICS_PATH, include_in_schema=False)
    def metrics() -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
