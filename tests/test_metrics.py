from prometheus_client import REGISTRY


def sample(name, labels=None):
    return REGISTRY.get_sample_value(name, labels or {}) or 0.0


def create_product(client, sku, quantity=5, price="20.00"):
    response = client.post(
        "/products",
        json={
            "name": f"Producto {sku}",
            "sku": sku,
            "price": price,
            "quantity": quantity,
            "minimum_stock": 1,
        },
    )
    assert response.status_code == 201
    return response.json()


def test_metrics_endpoint_exposes_prometheus_format(client):
    client.get("/health")

    response = client.get("/metrics")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    assert "nexo_http_requests_total" in response.text
    assert "nexo_http_request_duration_seconds_bucket" in response.text
    assert "nexo_orders_created_total" in response.text


def test_http_requests_are_counted_by_route_template(client):
    labels = {"method": "GET", "handler": "/orders/{order_id}", "status": "404"}
    before = sample("nexo_http_requests_total", labels)

    client.get("/orders/999999")

    assert sample("nexo_http_requests_total", labels) == before + 1
    assert sample(
        "nexo_http_request_duration_seconds_count",
        {"method": "GET", "handler": "/orders/{order_id}"},
    ) >= 1


def test_metrics_endpoint_is_not_self_instrumented(client):
    client.get("/metrics")

    assert sample(
        "nexo_http_requests_total",
        {"method": "GET", "handler": "/metrics", "status": "200"},
    ) == 0


def test_confirmed_order_updates_business_metrics(client):
    product = create_product(client, "MET-001", quantity=5, price="20.00")
    orders_before = sample("nexo_orders_created_total")
    revenue_before = sample("nexo_order_revenue_total")
    items_before = sample("nexo_order_items_sold_total")

    response = client.post(
        "/orders",
        json={"items": [{"product_id": product["id"], "quantity": 3}]},
    )

    assert response.status_code == 201
    assert sample("nexo_orders_created_total") == orders_before + 1
    assert sample("nexo_order_revenue_total") == revenue_before + 60.0
    assert sample("nexo_order_items_sold_total") == items_before + 3


def test_rejected_order_is_counted_by_reason(client):
    product = create_product(client, "MET-002", quantity=1)
    labels = {"reason": "insufficient_stock"}
    before = sample("nexo_orders_rejected_total", labels)
    orders_before = sample("nexo_orders_created_total")

    response = client.post(
        "/orders",
        json={"items": [{"product_id": product["id"], "quantity": 5}]},
    )

    assert response.status_code == 409
    assert sample("nexo_orders_rejected_total", labels) == before + 1
    assert sample("nexo_orders_created_total") == orders_before
