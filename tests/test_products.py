import pytest

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app

@pytest.fixture
def client():
    test_engine = create_engine(
        "sqlite+pysqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )

    Base.metadata.create_all(bind=test_engine)

    TestingSession = sessionmaker(bind=test_engine)

    def override_get_db():
        with TestingSession() as session:
            yield session

    app.dependency_overrides[get_db] = override_get_db

    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.clear()
        Base.metadata.drop_all(bind=test_engine)
        test_engine.dispose()

@pytest.fixture
def sample_product():
    return {
        "name": "Mouse inalámbrico",
        "sku": "MOU-001",
        "description": "Mouse ergonómico",
        "price": "29.99",
        "quantity": 15,
        "minimum_stock": 3,
    }

def test_create_product(client, sample_product):
    response = client.post("/products", json=sample_product)

    assert response.status_code == 201

    data = response.json()

    assert data["name"] == "Mouse inalámbrico"
    assert data["inventory"]["quantity"] == 15

def test_list_products(client, sample_product):
    client.post("/products", json=sample_product)

    response = client.get("/products")

    assert response.status_code == 200
    assert len(response.json()) == 1

def test_get_product(client, sample_product):
    created = client.post("/products", json=sample_product).json()

    response = client.get(f"/products/{created['id']}")

    assert response.status_code == 200
    assert response.json()["sku"] == "MOU-001"

def test_duplicate_sku(client, sample_product):
    client.post("/products", json=sample_product)

    response = client.post("/products", json=sample_product)

    assert response.status_code == 409

def test_negative_price(client, sample_product):
    sample_product["price"] = "-10.00"

    response = client.post("/products", json=sample_product)

    assert response.status_code == 422

def test_update_product(client, sample_product):
    created = client.post("/products", json=sample_product).json()

    response = client.put(
        f"/products/{created['id']}",
        json={"price": "39.99"},
    )

    assert response.status_code == 200
    assert response.json()["price"] == "39.99"

def test_delete_product(client, sample_product):
    created = client.post("/products", json=sample_product).json()

    response = client.delete(f"/products/{created['id']}")

    assert response.status_code == 204
    assert client.get(f"/products/{created['id']}").status_code == 404
