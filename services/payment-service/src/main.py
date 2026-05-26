"""
Payment Service - E-Commerce Platform
Handles payment processing and refunds.
"""

from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
from typing import Optional
from decimal import Decimal
from enum import Enum
import os, logging, asyncpg, uuid
from contextlib import asynccontextmanager

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("payment-service")

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://payment_service:password@localhost:5432/payment_service")


class PaymentStatus(str, Enum):
    PENDING = "pending"
    COMPLETED = "completed"
    FAILED = "failed"
    REFUNDED = "refunded"


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.db_pool = await asyncpg.create_pool(DATABASE_URL, min_size=5, max_size=20, command_timeout=60)
    async with app.state.db_pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS payments (
                id SERIAL PRIMARY KEY,
                payment_id VARCHAR(255) UNIQUE NOT NULL,
                order_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                amount DECIMAL(10,2) NOT NULL,
                currency VARCHAR(3) DEFAULT 'USD',
                status VARCHAR(50) DEFAULT 'pending',
                payment_method VARCHAR(50),
                transaction_id VARCHAR(255),
                created_at TIMESTAMP DEFAULT NOW(),
                updated_at TIMESTAMP DEFAULT NOW()
            )
        """)
    logger.info("Payment Service started successfully")
    yield
    await app.state.db_pool.close()


app = FastAPI(title="Payment Service", version="1.0.0", root_path="/api/v1/payments", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])


class PaymentCreate(BaseModel):
    order_id: int
    user_id: int
    amount: Decimal
    currency: str = "USD"
    payment_method: str


class PaymentResponse(BaseModel):
    id: int
    payment_id: str
    order_id: int
    user_id: int
    amount: Decimal
    currency: str
    status: str
    payment_method: str
    created_at: datetime


@app.get("/healthz", tags=["health"])
async def health_check():
    return {"status": "healthy", "service": "payment-service", "version": "1.0.0"}


@app.get("/readyz", tags=["health"])
async def readiness_check():
    try:
        async with app.state.db_pool.acquire() as conn:
            await conn.execute("SELECT 1")
        return {"status": "ready"}
    except Exception:
        raise HTTPException(status_code=503, detail="Service not ready")


@app.post("/", response_model=PaymentResponse, status_code=status.HTTP_201_CREATED, tags=["payments"])
async def create_payment(payment: PaymentCreate):
    payment_id = f"pay_{uuid.uuid4().hex[:16]}"
    async with app.state.db_pool.acquire() as conn:
        # Simulate payment processing
        row = await conn.fetchrow(
            """INSERT INTO payments (payment_id, order_id, user_id, amount, currency, status, payment_method)
               VALUES ($1, $2, $3, $4, $5, 'completed', $6)
               RETURNING id, payment_id, order_id, user_id, amount, currency, status, payment_method, created_at""",
            payment_id, payment.order_id, payment.user_id, payment.amount, payment.currency, payment.payment_method,
        )
        return PaymentResponse(**dict(row))


@app.get("/{payment_id}", response_model=PaymentResponse, tags=["payments"])
async def get_payment(payment_id: str):
    async with app.state.db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT * FROM payments WHERE payment_id = $1", payment_id)
        if not row:
            raise HTTPException(status_code=404, detail="Payment not found")
        return PaymentResponse(**dict(row))


@app.post("/{payment_id}/refund", tags=["payments"])
async def refund_payment(payment_id: str):
    async with app.state.db_pool.acquire() as conn:
        result = await conn.execute(
            "UPDATE payments SET status = 'refunded', updated_at = NOW() WHERE payment_id = $1 AND status = 'completed'",
            payment_id,
        )
        if result == "UPDATE 0":
            raise HTTPException(status_code=400, detail="Payment cannot be refunded")
        return {"message": f"Payment {payment_id} refunded"}
