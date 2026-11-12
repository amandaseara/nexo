from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from uuid import uuid4

import httpx

BASE_URL = "http://localhost:8000"

def create_product():
    response = httpx.post(
        f"{BASE_URL}/products",
        json={
            "name": "Producto concurrencia",
            "sku": f"CON-{uuid4().hex[:12]}",
            "price": "100.00",
            "quantity": 5,
            "minimum_stock": 1,
        },
        timeout=10,
    )

    response.raise_for_status()
    return response.json()["id"]

def create_order(product_id, barrier):
    barrier.wait()

    response = httpx.post(
        f"{BASE_URL}/orders",
        json={
            "items": [
                {
                    "product_id": product_id,
                    "quantity": 4,
                }
            ]
        },
        timeout=20,
    )

    return response.status_code

def main():
    product_id = create_product()
    barrier = Barrier(2)

    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [
            executor.submit(create_order, product_id, barrier)
            for _ in range(2)
        ]

        results = [future.result() for future in futures]

    inventory_response = httpx.get(
        f"{BASE_URL}/inventory/{product_id}",
        timeout=10,
    )

    inventory_response.raise_for_status()
    remaining_stock = inventory_response.json()["quantity"]

    print(f"Respuestas HTTP: {sorted(results)}")
    print(f"Stock restante: {remaining_stock}")

    assert sorted(results) == [201, 409], (
        "Se esperaba un pedido exitoso y otro rechazado"
    )

    assert remaining_stock == 1, (
        "El inventario no coincide con el resultado esperado"
    )

    print("PASS: control de concurrencia correcto")

if __name__ == "__main__":
    main()
