def create_product(client, sku="TEST-001", quantity=10):
    response = client.post(
        "/products",
        json={
            "name": "Producto de prueba",
            "sku": sku,
            "price": "50.00",
            "quantity": quantity,
            "minimum_stock": 2,
        },
    )

    assert response.status_code == 201
    return response.json()

def test_create_order(client):
    product = create_product(client)

    response = client.post(
        "/orders",
        json={
            "items": [
                {
                    "product_id": product["id"],
                    "quantity": 3,
                }
            ]
        },
    )

    assert response.status_code == 201
    assert response.json()["total_amount"] == "150.00"
    assert response.json()["status"] == "confirmed"

def test_order_reduces_stock(client):
    product = create_product(client, quantity=10)

    client.post(
        "/orders",
        json={
            "items": [
                {
                    "product_id": product["id"],
                    "quantity": 4,
                }
            ]
        },
    )

    response = client.get(
        f"/inventory/{product['id']}"
    )

    assert response.json()["quantity"] == 6

def test_insufficient_stock(client):
    product = create_product(client, quantity=5)

    response = client.post(
        "/orders",
        json={
            "items": [
                {
                    "product_id": product["id"],
                    "quantity": 10,
                }
            ]
        },
    )

    assert response.status_code == 409
    assert client.get("/orders").json() == []

    inventory = client.get(
        f"/inventory/{product['id']}"
    ).json()

    assert inventory["quantity"] == 5

def test_duplicate_products_in_order(client):
    product = create_product(client)

    response = client.post(
        "/orders",
        json={
            "items": [
                {"product_id": product["id"], "quantity": 1},
                {"product_id": product["id"], "quantity": 2},
            ]
        },
    )

    assert response.status_code == 422

def test_inactive_product_cannot_be_ordered(client):
    product = create_product(client)

    client.delete(f"/products/{product['id']}")

    response = client.post(
        "/orders",
        json={
            "items": [
                {"product_id": product["id"], "quantity": 1}
            ]
        },
    )

    assert response.status_code == 409

def test_inventory_adjustment(client):
    product = create_product(client, quantity=10)

    response = client.post(
        f"/inventory/{product['id']}/adjust",
        json={"adjustment": 5},
    )

    assert response.status_code == 200
    assert response.json()["quantity"] == 15

def test_negative_inventory_rejected(client):
    product = create_product(client, quantity=5)

    response = client.post(
        f"/inventory/{product['id']}/adjust",
        json={"adjustment": -10},
    )

    assert response.status_code == 409

    inventory = client.get(
        f"/inventory/{product['id']}"
    ).json()

    assert inventory["quantity"] == 5

def test_zero_inventory_adjustment_rejected(client):
    product = create_product(client)

    response = client.post(
        f"/inventory/{product['id']}/adjust",
        json={"adjustment": 0},
    )

    assert response.status_code == 422
