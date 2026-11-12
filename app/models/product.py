from decimal import Decimal

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    ForeignKey,
    Integer,
    Numeric,
    String,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base

class Product(Base):
    __tablename__ = "products"

    id: Mapped[int] = mapped_column(
        Integer, primary_key=True
    )

    name: Mapped[str] = mapped_column(
        String(150), nullable=False
    )

    sku: Mapped[str] = mapped_column(
        String(50), unique=True, nullable=False
    )

    description: Mapped[str | None] = mapped_column(
        String(500), nullable=True
    )

    price: Mapped[Decimal] = mapped_column(
        Numeric(12, 2), nullable=False
    )

    active: Mapped[bool] = mapped_column(
        Boolean, default=True, nullable=False
    )

    inventory: Mapped["Inventory"] = relationship(
        back_populates="product",
        cascade="all, delete-orphan",
        uselist=False,
        lazy="selectin",
    )

    __table_args__ = (
        CheckConstraint(
            "price >= 0",
            name="ck_product_price_nonnegative",
        ),
    )

class Inventory(Base):
    __tablename__ = "inventory"

    id: Mapped[int] = mapped_column(
        Integer, primary_key=True
    )

    product_id: Mapped[int] = mapped_column(
        ForeignKey("products.id"),
        unique=True,
        nullable=False,
    )

    quantity: Mapped[int] = mapped_column(
        Integer, default=0, nullable=False
    )

    minimum_stock: Mapped[int] = mapped_column(
        Integer, default=5, nullable=False
    )

    product: Mapped["Product"] = relationship(
        back_populates="inventory"
    )

    __table_args__ = (
        CheckConstraint(
            "quantity >= 0",
            name="ck_inventory_quantity_nonnegative",
        ),
        CheckConstraint(
            "minimum_stock >= 0",
            name="ck_inventory_minimum_nonnegative",
        ),
    )
