"""
Order Service - E-Commerce Platform
Handles cart, checkout, and order management.
"""

from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List
from decimal import Decimal
from enum import Enum
import os, logging, asyncpg, json
from contextlib import asynccontextmanager

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("order-service")

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://order_service:password@localhost:5432/order_service")


class OrderStatus(str, Enum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    PROCESSING = "processing"
    SHIPPED = "shipped"
    DELIVERED = "delivered"
    CANCELLED = "cancelled"


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.db_pool = await asyncpg.create_pool(DATABASE_URL, min_size=1, max_size=5, command_timeout=60)
    async with app.state.db_pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS orders (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL,
                status VARCHAR(50) DEFAULT 'pending',
                total_amount DECIMAL(10,2) NOT NULL,
                items JSONB NOT NULL,
                shipping_address JSONB,
                payment_id VARCHAR(255),
                created_at TIMESTAMP DEFAULT NOW(),
                updated_at TIMESTAMP DEFAULT NOW()
            )
        """)
    logger.info("Order Service started successfully")
    yield
    await app.state.db_pool.close()


app = FastAPI(title="Order Service", version="1.0.0", root_path="/api/v1/orders", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])


class OrderItem(BaseModel):
    product_id: int
    quantity: int
    price: Decimal


class OrderCreate(BaseModel):
    user_id: int
    items: List[OrderItem]
    shipping_address: Optional[dict] = None


class OrderResponse(BaseModel):
    id: int
    user_id: int
    status: str
    total_amount: Decimal
    items: list
    created_at: datetime


@app.get("/healthz", tags=["health"])
async def health_check():
    return {"status": "healthy", "service": "order-service", "version": "1.0.0"}


@app.get("/readyz", tags=["health"])
async def readiness_check():
    try:
        async with app.state.db_pool.acquire() as conn:
            await conn.execute("SELECT 1")
        return {"status": "ready"}
    except Exception:
        raise HTTPException(status_code=503, detail="Service not ready")


@app.post("/", response_model=OrderResponse, status_code=status.HTTP_201_CREATED, tags=["orders"])
async def create_order(order: OrderCreate):
    total = sum(item.price * item.quantity for item in order.items)
    items_json = json.dumps([item.model_dump(mode="json") for item in order.items])

    async with app.state.db_pool.acquire() as conn:
        row = await conn.fetchrow(
            """INSERT INTO orders (user_id, total_amount, items, shipping_address)
               VALUES ($1, $2, $3::jsonb, $4::jsonb)
               RETURNING id, user_id, status, total_amount, items, created_at""",
            order.user_id, total, items_json,
            json.dumps(order.shipping_address) if order.shipping_address else None,
        )
        result = dict(row)
        result["items"] = json.loads(result["items"]) if isinstance(result["items"], str) else result["items"]
        return OrderResponse(**result)


@app.get("/{order_id}", response_model=OrderResponse, tags=["orders"])
async def get_order(order_id: int):
    async with app.state.db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT id, user_id, status, total_amount, items, created_at FROM orders WHERE id = $1", order_id)
        if not row:
            raise HTTPException(status_code=404, detail="Order not found")
        result = dict(row)
        result["items"] = json.loads(result["items"]) if isinstance(result["items"], str) else result["items"]
        return OrderResponse(**result)


@app.get("/user/{user_id}", tags=["orders"])
async def get_user_orders(user_id: int, skip: int = 0, limit: int = 20):
    async with app.state.db_pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT id, user_id, status, total_amount, items, created_at FROM orders WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3",
            user_id, limit, skip,
        )
        results = []
        for row in rows:
            r = dict(row)
            r["items"] = json.loads(r["items"]) if isinstance(r["items"], str) else r["items"]
            results.append(OrderResponse(**r))
        return results


@app.patch("/{order_id}/status", tags=["orders"])
async def update_order_status(order_id: int, new_status: OrderStatus):
    async with app.state.db_pool.acquire() as conn:
        result = await conn.execute(
            "UPDATE orders SET status = $2, updated_at = NOW() WHERE id = $1", order_id, new_status.value,
        )
        if result == "UPDATE 0":
            raise HTTPException(status_code=404, detail="Order not found")
        return {"message": f"Order {order_id} status updated to {new_status.value}"}
